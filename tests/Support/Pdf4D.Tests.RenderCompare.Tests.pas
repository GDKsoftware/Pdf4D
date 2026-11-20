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

  public
    [Test]
    procedure TestIdenticalImagesAreEqual;

    [Test]
    procedure TestToleranceAllowsSmallDifferences;

    [Test]
    procedure TestFractionThreshold;

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

procedure TRenderCompareTests.TestToleranceAllowsSmallDifferences;
begin
  const Expected = Filled(10, 10, GrayBase);
  const AtTolerance = Filled(10, 10, GrayBase + TRenderCompare.PixelTolerance);
  const OverTolerance = Filled(10, 10, GrayBase + TRenderCompare.PixelTolerance + 1);
  try
    const Within = TRenderCompare.Compare(AtTolerance, Expected);
    const Beyond = TRenderCompare.Compare(OverTolerance, Expected);

    Assert.IsTrue(Within.IsEqual, 'a difference of 16 is within the tolerance');
    Assert.AreEqual(TRenderCompare.PixelTolerance, Within.MaxDifference);
    Assert.AreEqual(Int64(100), Beyond.DifferentPixels, 'a difference of 17 differs');
    Assert.IsFalse(Beyond.IsEqual);
  finally
    Expected.Free;
    AtTolerance.Free;
    OverTolerance.Free;
  end;
end;

procedure TRenderCompareTests.TestFractionThreshold;
begin
  const Expected = Filled(10, 10, GrayBase);
  const OneDifferent = Filled(10, 10, GrayBase);
  const TwoDifferent = Filled(10, 10, GrayBase);
  try
    SetGray(OneDifferent, 0, 0, 255);
    SetGray(TwoDifferent, 0, 0, 255);
    SetGray(TwoDifferent, 1, 0, 255);

    Assert.IsTrue(TRenderCompare.Compare(OneDifferent, Expected).IsEqual, '1 of 100 pixels is exactly the allowed share');
    Assert.IsFalse(TRenderCompare.Compare(TwoDifferent, Expected).IsEqual, '2 of 100 pixels is more than the allowed share');
  finally
    Expected.Free;
    OneDifferent.Free;
    TwoDifferent.Free;
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
