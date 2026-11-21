// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.RenderCompare.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Bitmap;

type
  [TestFixture]
  TRenderCompareTests = class
  private
    class function Filled(const Width, Height: Integer; const Value: Byte): TPdfBitmap; static;
    class procedure SetGray(const Bitmap: TPdfBitmap; const X, Y: Integer; const Value: Byte); static;
    class function PageWithBlock(const Left, Top, Size: Integer; const Value: Byte): TPdfBitmap; static;

  public
    [Test]
    procedure TestIdenticalImagesAreEqual;

    [Test]
    procedure TestFlatAreaNeedsATightMatch;

    [Test]
    procedure TestMissingBlockFails;

    [Test]
    procedure TestFlatFillThatIsOffByAQuarterFails;

    [Test]
    procedure TestAntiAliasNoiseAtEdgesPasses;

    [Test]
    procedure TestMisplacedEdgesFail;

    [Test]
    procedure TestFlatAndEdgePixelsAreCounted;

    [Test]
    procedure TestFlatFractionThreshold;

    // The distribution of the differences is what the tolerances are tuned on
    [Test]
    procedure TestDifferencesAreCountedPerValue;

    [Test]
    procedure TestSizeMismatchIsDifference;

    [Test]
    procedure TestKnownDifferenceSkipsPage;

    [Test]
    procedure TestPlatformQualifiedEntry;

    [Test]
    procedure TestPendingFileNotCounted;

    [Test]
    procedure TestPendingFileThatPassesFails;
  end;

implementation

uses
  System.IOUtils,
  Pdf4D.Tests.RenderCompare;

const
  GrayBase = 100;
  PageWidth = 595;
  PageHeight = 842;
  White = 255;

class function TRenderCompareTests.Filled(const Width, Height: Integer; const Value: Byte): TPdfBitmap;
begin
  Result := TPdfBitmap.Create(Width, Height);
  for var Y := 0 to Height - 1 do
  begin
    for var X := 0 to Width - 1 do
    begin
      SetGray(Result, X, Y, Value);
    end;
  end;
end;

class procedure TRenderCompareTests.SetGray(const Bitmap: TPdfBitmap; const X, Y: Integer; const Value: Byte);
begin
  Bitmap.SetPixel(X, Y, TPdfDeviceColor.Create(Value, Value, Value));
end;

procedure TRenderCompareTests.TestDifferencesAreCountedPerValue;
begin
  const Expected = Filled(10, 10, GrayBase);
  const Actual = Filled(10, 10, GrayBase);
  try
    for var X := 0 to 3 do
    begin
      SetGray(Actual, X, 0, GrayBase + 5);
    end;
    SetGray(Actual, 0, 9, GrayBase - 40);
    SetGray(Actual, 1, 9, GrayBase - 40);

    const Comparison = TRenderCompare.Compare(Actual, Expected);

    Assert.AreEqual(Int64(94), Comparison.FlatDifferences[0]);
    Assert.AreEqual(Int64(4), Comparison.FlatDifferences[5]);
    Assert.AreEqual(Int64(2), Comparison.FlatDifferences[40]);
    Assert.AreEqual(Int64(0), Comparison.EdgeDifferences[5]);
    Assert.AreEqual(Int64(0), Comparison.EdgeDifferences[0]);
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TRenderCompareTests.TestIdenticalImagesAreEqual;
begin
  const Actual = Filled(20, 10, GrayBase);
  const Expected = Filled(20, 10, GrayBase);
  try
    const Comparison = TRenderCompare.Compare(Actual, Expected);

    Assert.IsTrue(Comparison.IsEqual);
    Assert.AreEqual(Int64(0), Comparison.DifferentPixels);
    Assert.AreEqual(0, Comparison.MaxDifference);
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

// A white A4 page at 72 DPI (the size of the reference pages) with a gray rectangle
class function TRenderCompareTests.PageWithBlock(const Left, Top, Size: Integer; const Value: Byte): TPdfBitmap;
begin
  Result := Filled(PageWidth, PageHeight, White);
  for var Y := Top to Top + Size - 1 do
  begin
    for var X := Left to Left + Size - 1 do
    begin
      SetGray(Result, X, Y, Value);
    end;
  end;
end;

procedure TRenderCompareTests.TestFlatAreaNeedsATightMatch;
begin
  const Expected = Filled(100, 100, GrayBase);
  const Close = Filled(100, 100, GrayBase + 8);
  const Further = Filled(100, 100, GrayBase + 9);
  try
    Assert.IsTrue(TRenderCompare.Compare(Close, Expected).IsEqual, 'a difference of 8 in a flat area is within the tolerance');
    Assert.IsFalse(TRenderCompare.Compare(Further, Expected).IsEqual, 'a difference of 9 in a flat area is not');
  finally
    Expected.Free;
    Close.Free;
    Further.Free;
  end;
end;

// A block of 68 x 68 pixels that the render does not have is 0.9% of an A4 page at 72 DPI
procedure TRenderCompareTests.TestMissingBlockFails;
begin
  const Expected = PageWithBlock(100, 100, 68, 40);
  const Actual = Filled(PageWidth, PageHeight, White);
  try
    Assert.IsFalse(TRenderCompare.Compare(Actual, Expected).IsEqual);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

// A fill that is 25% too dark in a block of 100 x 100 pixels: the difference of 50 levels is no coverage noise
procedure TRenderCompareTests.TestFlatFillThatIsOffByAQuarterFails;
begin
  const Expected = PageWithBlock(100, 100, 100, 200);
  const Actual = PageWithBlock(100, 100, 100, 150);
  try
    Assert.IsFalse(TRenderCompare.Compare(Actual, Expected).IsEqual);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

// The pixels on the border of a shape get another coverage from another rasterizer: half of the way to the other side is no failure
procedure TRenderCompareTests.TestAntiAliasNoiseAtEdgesPasses;
begin
  const Expected = PageWithBlock(100, 100, 100, 0);
  const Actual = PageWithBlock(100, 100, 100, 0);
  try
    for var Index := 100 to 199 do
    begin
      // the first and the last column and row of the block are the pixels next to the edge
      SetGray(Actual, 100, Index, 80);
      SetGray(Actual, 199, Index, 80);
      SetGray(Actual, Index, 100, 80);
      SetGray(Actual, Index, 199, 80);
      SetGray(Actual, 99, Index, 175);
      SetGray(Actual, Index, 99, 175);
    end;

    const Comparison = TRenderCompare.Compare(Actual, Expected);

    Assert.IsTrue(Comparison.IsEqual, Comparison.Describe);
    Assert.IsTrue(Comparison.EdgePixels > 0);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

// Edges that are drawn somewhere else (more than 3% of the edge pixels beyond the wide tolerance) are a failure too
procedure TRenderCompareTests.TestMisplacedEdgesFail;
begin
  const Expected = PageWithBlock(100, 100, 100, 0);
  const Actual = PageWithBlock(105, 100, 100, 0);
  try
    Assert.IsFalse(TRenderCompare.Compare(Actual, Expected).IsEqual);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

// The share of flat pixels that may differ is 0.02%: 10 of 50000, not 11
procedure TRenderCompareTests.TestFlatFractionThreshold;
begin
  const Expected = Filled(500, 100, GrayBase);
  const TenDifferent = Filled(500, 100, GrayBase);
  const ElevenDifferent = Filled(500, 100, GrayBase);
  try
    for var X := 0 to 9 do
    begin
      SetGray(TenDifferent, X, 0, 255);
      SetGray(ElevenDifferent, X, 0, 255);
    end;
    SetGray(ElevenDifferent, 10, 0, 255);

    Assert.IsTrue(TRenderCompare.Compare(TenDifferent, Expected).IsEqual, '10 of 50000 flat pixels is the allowed share');
    Assert.IsFalse(TRenderCompare.Compare(ElevenDifferent, Expected).IsEqual, '11 of 50000 flat pixels is more');
  finally
    Expected.Free;
    TenDifferent.Free;
    ElevenDifferent.Free;
  end;
end;

procedure TRenderCompareTests.TestFlatAndEdgePixelsAreCounted;
begin
  const Expected = PageWithBlock(10, 10, 20, 0);
  const Actual = PageWithBlock(10, 10, 20, 0);
  try
    const Comparison = TRenderCompare.Compare(Actual, Expected);

    Assert.AreEqual(Int64(PageWidth) * PageHeight, Comparison.TotalPixels);
    Assert.AreEqual(Comparison.TotalPixels, Comparison.FlatPixels + Comparison.EdgePixels);
    // the ring of pixels on each side of the border of the block: 22 x 22 minus 18 x 18
    Assert.AreEqual(Int64(22 * 22 - 18 * 18), Comparison.EdgePixels);
    Assert.AreEqual(Int64(0), Comparison.DifferentPixels);
  finally
    Expected.Free;
    Actual.Free;
  end;
end;

procedure TRenderCompareTests.TestSizeMismatchIsDifference;
begin
  const Actual = Filled(10, 10, GrayBase);
  const Expected = Filled(10, 11, GrayBase);
  try
    const Comparison = TRenderCompare.Compare(Actual, Expected);

    Assert.IsFalse(Comparison.HasSameSize);
    Assert.IsFalse(Comparison.IsEqual);
  finally
    Actual.Free;
    Expected.Free;
  end;
end;

procedure TRenderCompareTests.TestKnownDifferenceSkipsPage;
begin
  const Entries: TArray<string> = ['page 2 # the image uses upsampling that differs', '', 'page 10 # another page'];

  Assert.IsTrue(TRenderCompare.IsKnownDifference(Entries, 2, 'Win64'));
  Assert.IsTrue(TRenderCompare.IsKnownDifference(Entries, 10, 'Linux64'));
  Assert.IsFalse(TRenderCompare.IsKnownDifference(Entries, 1, 'Win64'));
  Assert.IsFalse(TRenderCompare.IsKnownDifference(Entries, 3, 'Win64'));
end;

procedure TRenderCompareTests.TestPlatformQualifiedEntry;
begin
  const Entries: TArray<string> = ['page 4 [Linux64] # fonts differ on Linux'];

  Assert.IsTrue(TRenderCompare.IsKnownDifference(Entries, 4, 'Linux64'));
  Assert.IsFalse(TRenderCompare.IsKnownDifference(Entries, 4, 'Win64'));
  Assert.IsFalse(TRenderCompare.IsKnownDifference(Entries, 5, 'Linux64'));
end;

procedure TRenderCompareTests.TestPendingFileNotCounted;
begin
  const FileName = TPath.Combine(TPath.GetTempPath, 'pdf4d-pending-test.txt');
  TFile.WriteAllText(FileName, '# comment' + sLineBreak + 'generated/render/shadings.pdf # Task 20: shadings' + sLineBreak + sLineBreak +
                               'generated/render/patterns.pdf # Task 22: tiling patterns' + sLineBreak, TEncoding.UTF8);
  try
    const Pending = TRenderCompare.PendingFiles(FileName);
    const Verdict = TRenderCompare.Judge(True, ['page 1: 40.000% of the pixels differ']);

    Assert.AreEqual<Integer>(2, Length(Pending));
    Assert.AreEqual('generated/render/shadings.pdf', Pending[0]);
    Assert.AreEqual('generated/render/patterns.pdf', Pending[1]);
    Assert.IsFalse(Verdict.IsFailure, 'a pending file that differs is reported and does not fail');
    Assert.AreEqual<Integer>(0, Length(TRenderCompare.PendingFiles(FileName + '.missing')));
  finally
    TFile.Delete(FileName);
  end;
end;

procedure TRenderCompareTests.TestPendingFileThatPassesFails;
begin
  const Verdict = TRenderCompare.Judge(True, nil);

  Assert.IsTrue(Verdict.IsFailure);
  Assert.IsTrue(Verdict.Message.Contains('remove from pending.txt'));
  Assert.IsFalse(TRenderCompare.Judge(False, nil).IsFailure);
  Assert.IsTrue(TRenderCompare.Judge(False, ['page 1: different size']).IsFailure);
end;

end.
