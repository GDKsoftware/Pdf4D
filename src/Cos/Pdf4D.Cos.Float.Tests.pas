unit Pdf4D.Cos.Float.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCosFloatTests = class
  private
    procedure AssertParses(const Text: string; const Expected: Single);
    procedure AssertParseRaises(const Text: string);

  public
    [Test]
    procedure TestParseTolerantFloats;

    [Test]
    procedure TestParseDoubleNegative;

    [Test]
    procedure TestParseMisplacedNegative;

    [Test]
    procedure TestParseMisplacedNegativeWithTwoMinusSignsRaises;

    [Test]
    procedure TestParseGarbageRaises;

    [Test]
    procedure TestParseVerySmallValuesBecomeZero;

    [Test]
    procedure TestParseVeryLargeValuesAreClamped;

    [Test]
    procedure TestParseValueBeyondDoubleRange;

    [Test]
    procedure TestParseVeryLongTokenIsFast;

    [Test]
    procedure TestParseWhitespaceAndSuffix;

    [Test]
    procedure TestIntAndLongValueTruncate;

    [Test]
    procedure TestIntAndLongValueSaturate;

    [Test]
    procedure TestIntegerValues;

    [Test]
    procedure TestOutOfRangeInteger;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer;

{ TCosFloatTests }

procedure TCosFloatTests.AssertParses(const Text: string; const Expected: Single);
begin
  const Number = TCosFloat.Parse(Text);
  try
    Assert.AreEqual<Single>(Expected, Number.FloatValue, Text);
  finally
    Number.Free;
  end;
end;

procedure TCosFloatTests.AssertParseRaises(const Text: string);
begin
  Assert.WillRaise(
    procedure
    begin
      TCosFloat.Parse(Text).Free;
    end,
    EPdfParseException,
    Text);
end;

procedure TCosFloatTests.TestParseTolerantFloats;
begin
  AssertParses('1.5', 1.5);
  AssertParses('-.5', -0.5);
  AssertParses('+3', 3);
  AssertParses('5.', 5);
  AssertParses('0', 0);
  AssertParses('1e2', 100);
  AssertParses('--1', -1);
  // PDFBox 3.0.8 repairs '0.00-5' to -0.005
  AssertParses('0.00-5', -0.005);
  // PDFBox 3.0.8 does not repair '1.-2'
  AssertParseRaises('1.-2');
end;

procedure TCosFloatTests.TestParseDoubleNegative;
begin
  // PDFBOX-4289
  AssertParses('--16.33', -16.33);
end;

procedure TCosFloatTests.TestParseMisplacedNegative;
begin
  // PDFBOX-2990, PDFBOX-3369 and PDFBOX-3500
  AssertParses('0.00000-33917698', -0.0000033917698);
  AssertParses('0.-262', -0.262);
  AssertParses('-0.-262', -0.262);
  // PDFBOX-5829
  AssertParses('-12.-1', -12.1);
end;

procedure TCosFloatTests.TestParseMisplacedNegativeWithTwoMinusSignsRaises;
begin
  AssertParseRaises('0.-26-2');
  AssertParseRaises('---0.262');
  AssertParseRaises('--0.2-62');
end;

procedure TCosFloatTests.TestParseGarbageRaises;
begin
  AssertParseRaises('abc');
  AssertParseRaises('');
  AssertParseRaises('-');
  AssertParseRaises('.');
  AssertParseRaises('1e');
  AssertParseRaises('1.5.2');
  AssertParseRaises('NaN');
end;

procedure TCosFloatTests.TestParseVerySmallValuesBecomeZero;
begin
  AssertParses('1.4012984643248171E-46', 0);
  AssertParses('-1.4012984643248171E-46', 0);
  AssertParses('0.00000000000000000000000000000000000000000000014012984643248171', 0);
  AssertParses('-0.00000000000000000000000000000000000000000000014012984643248171', 0);
  AssertParses('1e-400', 0);
end;

procedure TCosFloatTests.TestParseVeryLargeValuesAreClamped;
begin
  AssertParses('3.4028234663852886E39', 3.4028234663852886E38);
  AssertParses('-3.4028234663852886E39', -3.4028234663852886E38);
  AssertParses('340282346638528860000000000000000000000000', 3.4028234663852886E38);
  AssertParses('-340282346638528860000000000000000000000000', -3.4028234663852886E38);
end;

procedure TCosFloatTests.TestParseVeryLongTokenIsFast;
begin
  const Watch = TStopwatch.StartNew;
  const Number = TCosFloat.Parse('1.' + StringOfChar('5', 2 * 1024 * 1024));
  try
    Assert.AreEqual<Single>(1.5555556, Number.FloatValue);
  finally
    Number.Free;
  end;
  AssertParses('1' + StringOfChar('0', 2 * 1024 * 1024), 3.4028234663852886E38);
  AssertParses('0.' + StringOfChar('0', 2 * 1024 * 1024) + '1', 0);
  AssertParses('1.' + StringOfChar('0', 350), 1);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 3000, 'a long number token must be parsed in linear time');
end;

procedure TCosFloatTests.TestParseValueBeyondDoubleRange;
begin
  AssertParses('1e400', 3.4028234663852886E38);
  AssertParses('-1e400', -3.4028234663852886E38);
  AssertParses('1e99999999999999999999', 3.4028234663852886E38);
  AssertParses('1e-99999999999999999999', 0);
end;

procedure TCosFloatTests.TestParseWhitespaceAndSuffix;
begin
  AssertParses(' 1.5 ', 1.5);
  AssertParses('1.5f', 1.5);
  AssertParseRaises('f');
end;

procedure TCosFloatTests.TestIntAndLongValueTruncate;
begin
  const Number = TCosFloat.Create(-12.75);
  try
    Assert.AreEqual(-12, Number.IntValue);
    Assert.AreEqual<Int64>(-12, Number.LongValue);
    Assert.AreEqual<Single>(-12.75, Number.FloatValue);
  finally
    Number.Free;
  end;
end;

procedure TCosFloatTests.TestIntAndLongValueSaturate;
begin
  const Large = TCosFloat.Create(3.0E38);
  try
    Assert.AreEqual(High(Integer), Large.IntValue);
    Assert.AreEqual(High(Int64), Large.LongValue);
  finally
    Large.Free;
  end;

  const Small = TCosFloat.Create(-3.0E38);
  try
    Assert.AreEqual(Low(Integer), Small.IntValue);
    Assert.AreEqual(Low(Int64), Small.LongValue);
  finally
    Small.Free;
  end;
end;

procedure TCosFloatTests.TestIntegerValues;
begin
  const Number = TCosInteger.Create(5000000000);
  try
    Assert.AreEqual<Int64>(5000000000, Number.LongValue);
    Assert.AreEqual<Int64>(5000000000, Number.Value);
    // Truncated to 32 bits like the (int) cast in Java
    Assert.AreEqual(705032704, Number.IntValue);
    Assert.AreEqual<Single>(5000000000, Number.FloatValue);
    Assert.IsTrue(Number.IsValid);
    Assert.IsFalse(Number.Direct);
  finally
    Number.Free;
  end;
end;

procedure TCosFloatTests.TestOutOfRangeInteger;
begin
  const TooLarge = TCosInteger.CreateOutOfRange(True);
  const TooSmall = TCosInteger.CreateOutOfRange(False);
  try
    Assert.IsFalse(TooLarge.IsValid);
    Assert.IsFalse(TooSmall.IsValid);
    Assert.AreEqual(High(Int64), TooLarge.LongValue);
    Assert.AreEqual(Low(Int64), TooSmall.LongValue);
  finally
    TooSmall.Free;
    TooLarge.Free;
  end;
end;

end.
