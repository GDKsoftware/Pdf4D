// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.Standard14.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  DUnitX.TestFramework,
  Pdf4D.FontBox.Afm;

type
  // Asks for the shared metrics as soon as all threads are ready
  TStandard14Thread = class(TThread)
  private
    FStart: TObject;
    FResult: TFontMetrics;
    FFailure: string;

  protected
    procedure Execute; override;

  public
    constructor Create(const Start: TObject);

    property Result: TFontMetrics read FResult;
    property Failure: string read FFailure;
  end;

  [TestFixture]
  TStandard14FontsTests = class
  private
    function MetricsOf(const Name: string): TFontMetrics;
    procedure CheckWidth(const Name, GlyphName: string; const Expected: Single);

  public
    [Test]
    procedure TestHelveticaMetrics;

    [Test]
    procedure TestHelveticaKerningIsNotLoaded;

    [Test]
    procedure TestOtherCoreFonts;

    [Test]
    procedure TestEveryStandardFontHasMetrics;

    [Test]
    procedure TestAliases;

    [Test]
    procedure TestPostScriptNames;

    [Test]
    procedure TestUnknownNameHasNoMetrics;

    [Test]
    procedure TestAfmIsSharedAndLoadedOnce;

    [Test]
    procedure TestAliasesShareTheMetricsOfTheirFont;

    [Test]
    procedure TestAfmConcurrentFirstUse;
  end;

implementation

uses
  System.SyncObjs,
  Pdf4D.Font.Standard14;

type
  TStartSignal = class
  public
    Gate: TEvent;

    constructor Create;
    destructor Destroy; override;
  end;

{ TStartSignal }

constructor TStartSignal.Create;
begin
  inherited Create;
  Gate := TEvent.Create(nil, True, False, '');
end;

destructor TStartSignal.Destroy;
begin
  Gate.Free;
  inherited;
end;

{ TStandard14Thread }

constructor TStandard14Thread.Create(const Start: TObject);
begin
  FStart := Start;
  inherited Create(False);
end;

procedure TStandard14Thread.Execute;
begin
  try
    TStartSignal(FStart).Gate.WaitFor(INFINITE);
    if not TStandard14Fonts.TryGetAFM('Courier-Bold', FResult) then
    begin
      FFailure := 'No metrics for Courier-Bold';
    end;
  except
    on E: Exception do
    begin
      FFailure := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TStandard14FontsTests }

function TStandard14FontsTests.MetricsOf(const Name: string): TFontMetrics;
begin
  Assert.IsTrue(TStandard14Fonts.TryGetAFM(Name, Result), Format('No metrics for %s', [Name]));
end;

procedure TStandard14FontsTests.CheckWidth(const Name, GlyphName: string; const Expected: Single);
begin
  Assert.AreEqual(Double(Expected), Double(MetricsOf(Name).GetCharacterWidth(GlyphName)), 0.0,
                  Format('Width of %s in %s', [GlyphName, Name]));
end;

procedure TStandard14FontsTests.TestHelveticaMetrics;
begin
  CheckWidth('Helvetica', 'space', 278);
  CheckWidth('Helvetica', 'A', 667);
  CheckWidth('Helvetica', 'H', 722);
  CheckWidth('Helvetica', 'Euro', 556);
  CheckWidth('Helvetica', 'NoSuchGlyph', 0);

  const Metrics = MetricsOf('Helvetica');
  Assert.IsTrue(Metrics.HasFontBBox);
  Assert.AreEqual(Double(-166), Double(Metrics.FontBBox.LowerLeftX), 0.0);
  Assert.AreEqual(Double(-225), Double(Metrics.FontBBox.LowerLeftY), 0.0);
  Assert.AreEqual(Double(1000), Double(Metrics.FontBBox.UpperRightX), 0.0);
  Assert.AreEqual(Double(931), Double(Metrics.FontBBox.UpperRightY), 0.0);
  Assert.AreEqual(Double(718), Double(Metrics.CapHeight), 0.0);
  Assert.AreEqual(Double(718), Double(Metrics.Ascender), 0.0);
  Assert.AreEqual(Double(-207), Double(Metrics.Descender), 0.0);
end;

procedure TStandard14FontsTests.TestHelveticaKerningIsNotLoaded;
begin
  // PDFBox loads the standard 14 AFMs as a reduced dataset; the kerning pair KPX A V -70 is in the file but not in memory
  Assert.AreEqual<Integer>(0, MetricsOf('Helvetica').KernPairs.Count);
end;

procedure TStandard14FontsTests.TestOtherCoreFonts;
begin
  CheckWidth('Times-Roman', 'space', 250);
  CheckWidth('Courier', 'A', 600);
  CheckWidth('Symbol', 'alpha', 631);
  CheckWidth('ZapfDingbats', 'a1', 974);
end;

procedure TStandard14FontsTests.TestEveryStandardFontHasMetrics;
begin
  for var FontName := Low(TStandard14FontName) to High(TStandard14FontName) do
  begin
    const Metrics = MetricsOf(TStandard14Fonts.PostScriptName(FontName));
    Assert.IsTrue(Metrics.CharMetrics.Count > 100, Format('Too few glyphs in %s', [TStandard14Fonts.PostScriptName(FontName)]));
    Assert.AreEqual(TStandard14Fonts.PostScriptName(FontName), Metrics.FontName);
  end;
end;

procedure TStandard14FontsTests.TestAliases;
begin
  var FontName: TStandard14FontName;
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('Arial,Bold', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.HelveticaBold, FontName);
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('TimesNewRoman,BoldItalic', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.TimesBoldItalic, FontName);
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('CourierNew', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.Courier, FontName);
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('Arial-BoldItalicMT', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.HelveticaBoldOblique, FontName);
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('Symbol,BoldItalic', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.Symbol, FontName);
  Assert.IsTrue(TStandard14Fonts.TryGetMappedFontName('Times-Italic', FontName));
  Assert.AreEqual<TStandard14FontName>(TStandard14FontName.TimesItalic, FontName);

  Assert.IsFalse(TStandard14Fonts.TryGetMappedFontName('Foo', FontName));
  Assert.IsTrue(TStandard14Fonts.ContainsName('ArialMT'));
  Assert.IsFalse(TStandard14Fonts.ContainsName('Foo'));
  Assert.IsFalse(TStandard14Fonts.ContainsName('arial'), 'Names are case sensitive, as in PDFBox');
end;

procedure TStandard14FontsTests.TestPostScriptNames;
begin
  Assert.AreEqual('Times-Roman', TStandard14Fonts.PostScriptName(TStandard14FontName.TimesRoman));
  Assert.AreEqual('Helvetica-BoldOblique', TStandard14Fonts.PostScriptName(TStandard14FontName.HelveticaBoldOblique));
  Assert.AreEqual('Courier-Oblique', TStandard14Fonts.PostScriptName(TStandard14FontName.CourierOblique));
  Assert.AreEqual('ZapfDingbats', TStandard14Fonts.PostScriptName(TStandard14FontName.ZapfDingbats));
end;

procedure TStandard14FontsTests.TestUnknownNameHasNoMetrics;
begin
  var Metrics: TFontMetrics;
  Assert.IsFalse(TStandard14Fonts.TryGetAFM('Foo', Metrics));
  Assert.IsNull(Metrics);
end;

procedure TStandard14FontsTests.TestAfmIsSharedAndLoadedOnce;
begin
  Assert.AreSame(MetricsOf('Helvetica'), MetricsOf('Helvetica'));
end;

procedure TStandard14FontsTests.TestAliasesShareTheMetricsOfTheirFont;
begin
  Assert.AreSame(MetricsOf('Helvetica-Bold'), MetricsOf('Arial,Bold'));
  Assert.AreNotSame(MetricsOf('Helvetica'), MetricsOf('Helvetica-Bold'));
end;

procedure TStandard14FontsTests.TestAfmConcurrentFirstUse;
begin
  const ThreadCount = 8;
  const Signal = TStartSignal.Create;
  try
    var Threads: TArray<TStandard14Thread>;
    SetLength(Threads, ThreadCount);
    for var Index := 0 to ThreadCount - 1 do
    begin
      Threads[Index] := TStandard14Thread.Create(Signal);
    end;

    Signal.Gate.SetEvent;
    for var Thread in Threads do
    begin
      Thread.WaitFor;
    end;

    try
      for var Thread in Threads do
      begin
        Assert.AreEqual('', Thread.Failure);
        Assert.AreSame(MetricsOf('Courier-Bold'), Thread.Result);
      end;
    finally
      for var Thread in Threads do
      begin
        Thread.Free;
      end;
    end;
  finally
    Signal.Free;
  end;
end;

end.
