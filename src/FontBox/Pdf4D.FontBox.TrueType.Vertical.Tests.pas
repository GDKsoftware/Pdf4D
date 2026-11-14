// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/VerticalHeaderTable.java (3.0.8)
// Port of: fontbox/src/main/java/org/apache/fontbox/ttf/VerticalMetricsTable.java (3.0.8)
unit Pdf4D.FontBox.TrueType.Vertical.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.FontBox.TrueType.Vertical,
  Pdf4D.Tests.TrueTypeBuilder;

type
  [TestFixture]
  TTrueTypeVerticalTests = class
  private
    const LiberationSans = 'LiberationSans-Regular.ttf';

  private
    class function VerticalHeaderBytes(const NumberOfVMetrics: Integer): TBytes; static;
    class function VerticalMetricsBytes: TBytes; static;
    class procedure ReadMetricsTable(const Host: TTestTableHost; const Bytes: TBytes); static;
    class function LoadHeader(const Host: TTestTableHost; const Bytes: TBytes): TVerticalHeaderTable; static;
    class function LoadMetrics(const Host: TTestTableHost; const Bytes: TBytes): TVerticalMetricsTable; static;

  public
    [Test]
    procedure TestHeaderFields;

    [Test]
    procedure TestMetricsOfGlyphsInsideAndBeyondTheExplicitOnes;

    [Test]
    procedure TestNegativeGlyphIdRaises;

    [Test]
    procedure TestMetricsWithoutHeaderRaise;

    [Test]
    procedure TestMoreMetricsThanDataRaises;

    [Test]
    procedure TestFontExposesTheVerticalTables;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.TrueType.DataStream,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.FontBox.TrueType.Parser,
  Pdf4D.Tests.TestFonts;

{ TTrueTypeVerticalTests }

class function TTrueTypeVerticalTests.VerticalHeaderBytes(const NumberOfVMetrics: Integer): TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U32($00010000);
    Writer.U16(880); // ascender
    Writer.U16(-120 and $FFFF); // descender
    Writer.U16(10); // line gap
    Writer.U16(1000); // advance height max
    Writer.U16(20); // min top side bearing
    Writer.U16(30); // min bottom side bearing
    Writer.U16(900); // y max extent
    Writer.U16(1); // caret slope rise
    Writer.U16(0); // caret slope run
    Writer.U16(0); // caret offset
    Writer.Zeros(8); // reserved
    Writer.U16(0); // metric data format
    Writer.U16(NumberOfVMetrics);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

// Three explicit metrics, then the top side bearings of two more glyphs
class function TTrueTypeVerticalTests.VerticalMetricsBytes: TBytes;
begin
  const Writer = TTestByteWriter.Create;
  try
    Writer.U16(1000);
    Writer.U16(11);
    Writer.U16(900);
    Writer.U16(12);
    Writer.U16(800);
    Writer.U16(-13 and $FFFF);
    Writer.U16(21);
    Writer.U16(22);
    Result := Writer.ToBytes;
  finally
    Writer.Free;
  end;
end;

class procedure TTrueTypeVerticalTests.ReadMetricsTable(const Host: TTestTableHost; const Bytes: TBytes);
begin
  LoadMetrics(Host, Bytes);
end;

class function TTrueTypeVerticalTests.LoadHeader(const Host: TTestTableHost; const Bytes: TBytes): TVerticalHeaderTable;
begin
  Result := TVerticalHeaderTable.Create(TVerticalHeaderTable.TableTag, 0, 0, Length(Bytes));
  Host.AddTable(Result);
  const Stream = TTTFMemoryDataStream.Create(Bytes);
  try
    Result.Read(Host, Stream);
  finally
    Stream.Free;
  end;
end;

class function TTrueTypeVerticalTests.LoadMetrics(const Host: TTestTableHost; const Bytes: TBytes): TVerticalMetricsTable;
begin
  Result := TVerticalMetricsTable.Create(TVerticalMetricsTable.TableTag, 0, 0, Length(Bytes));
  Host.AddTable(Result);
  const Stream = TTTFMemoryDataStream.Create(Bytes);
  try
    Result.Read(Host, Stream);
  finally
    Stream.Free;
  end;
end;

procedure TTrueTypeVerticalTests.TestHeaderFields;
begin
  const Host = TTestTableHost.Create(5);
  try
    const Header = LoadHeader(Host, VerticalHeaderBytes(3));

    Assert.AreEqual(Double(1), Double(Header.Version));
    Assert.AreEqual<Integer>(880, Integer(Header.Ascender));
    Assert.AreEqual<Integer>(-120, Integer(Header.Descender));
    Assert.AreEqual<Integer>(10, Integer(Header.LineGap));
    Assert.AreEqual<Integer>(1000, Header.AdvanceHeightMax);
    Assert.AreEqual<Integer>(20, Integer(Header.MinTopSideBearing));
    Assert.AreEqual<Integer>(30, Integer(Header.MinBottomSideBearing));
    Assert.AreEqual<Integer>(900, Integer(Header.YMaxExtent));
    Assert.AreEqual<Integer>(3, Header.NumberOfVMetrics);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeVerticalTests.TestMetricsOfGlyphsInsideAndBeyondTheExplicitOnes;
begin
  const Host = TTestTableHost.Create(5);
  try
    LoadHeader(Host, VerticalHeaderBytes(3));
    const Metrics = LoadMetrics(Host, VerticalMetricsBytes);

    Assert.AreEqual<Integer>(1000, Metrics.GetAdvanceHeight(0));
    Assert.AreEqual<Integer>(800, Metrics.GetAdvanceHeight(2));
    Assert.AreEqual<Integer>(800, Metrics.GetAdvanceHeight(3), 'the last advance height holds for the rest');
    Assert.AreEqual<Integer>(800, Metrics.GetAdvanceHeight(60000));
    Assert.AreEqual<Integer>(11, Metrics.GetTopSideBearing(0));
    Assert.AreEqual<Integer>(-13, Metrics.GetTopSideBearing(2));
    Assert.AreEqual<Integer>(21, Metrics.GetTopSideBearing(3));
    Assert.AreEqual<Integer>(22, Metrics.GetTopSideBearing(4));
    Assert.AreEqual<Integer>(0, Metrics.GetTopSideBearing(60000), 'a glyph without a bearing has 0');
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeVerticalTests.TestNegativeGlyphIdRaises;
begin
  const Host = TTestTableHost.Create(5);
  try
    LoadHeader(Host, VerticalHeaderBytes(3));
    const Metrics = LoadMetrics(Host, VerticalMetricsBytes);

    Assert.WillRaise(
      procedure
      begin
        Metrics.GetAdvanceHeight(-1);
      end,
      EPdfParseException);
    Assert.WillRaise(
      procedure
      begin
        Metrics.GetTopSideBearing(-1);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeVerticalTests.TestMetricsWithoutHeaderRaise;
begin
  const Host = TTestTableHost.Create(5);
  try
    const Bytes = VerticalMetricsBytes;

    Assert.WillRaise(
      procedure
      begin
        ReadMetricsTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

procedure TTrueTypeVerticalTests.TestMoreMetricsThanDataRaises;
begin
  const Host = TTestTableHost.Create(5);
  try
    LoadHeader(Host, VerticalHeaderBytes(60000));
    const Bytes = VerticalMetricsBytes;

    Assert.WillRaise(
      procedure
      begin
        ReadMetricsTable(Host, Bytes);
      end,
      EPdfParseException);
  finally
    Host.Free;
  end;
end;

// The font has neither table; two tables it does not need are changed into them
procedure TTrueTypeVerticalTests.TestFontExposesTheVerticalTables;
begin
  const Data = TTestFonts.Bytes(LiberationSans);
  TTrueTypeTestData.ReplaceTable(Data, 'prep', TVerticalHeaderTable.TableTag, VerticalHeaderBytes(3));
  TTrueTypeTestData.ReplaceTable(Data, 'fpgm', TVerticalMetricsTable.TableTag, VerticalMetricsBytes);

  const Parser = TTTFParser.Create;
  try
    const Font = Parser.Parse(Data);
    try
      var Header: TVerticalHeaderTable;
      var Metrics: TVerticalMetricsTable;
      Assert.IsTrue(Font.TryGetVerticalHeader(Header));
      Assert.IsTrue(Font.TryGetVerticalMetrics(Metrics));

      Assert.AreEqual<Integer>(3, Header.NumberOfVMetrics);
      Assert.AreEqual<Integer>(900, Metrics.GetAdvanceHeight(1));
      Assert.AreEqual<Integer>(22, Metrics.GetTopSideBearing(4));
    finally
      Font.Free;
    end;
  finally
    Parser.Free;
  end;
end;

end.
