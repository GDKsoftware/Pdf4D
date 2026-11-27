// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Tests of tiny-skia v0.12.0 src/blitter.rs: the default methods of the Blitter trait are unreachable!()
unit Pdf4D.Render.Native.Blitter.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.AlphaRuns,
  Pdf4D.Render.Native.Blitter;

type
  TTsHorizontalOnlyBlitter = class(TTsBlitter)
  private
    FBlitted: Cardinal;

  public
    procedure BlitH(const X, Y, Width: Cardinal); override;

    property Blitted: Cardinal read FBlitted;
  end;

  TTsNothingBlitter = class(TTsBlitter)
  end;

  [TestFixture]
  TTsBlitterTests = class
  private
    FBlitter: TTsHorizontalOnlyBlitter;

    procedure CallBlitH;
    procedure CallBlitAntiH;
    procedure CallBlitV;
    procedure CallBlitAntiH2;
    procedure CallBlitAntiV2;
    procedure CallBlitRect;
    procedure CallBlitMask;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestOverriddenMethodIsCalled;

    [Test]
    procedure TestBlitAntiHIsNotImplementedByDefault;

    [Test]
    procedure TestBlitVIsNotImplementedByDefault;

    [Test]
    procedure TestBlitAntiH2IsNotImplementedByDefault;

    [Test]
    procedure TestBlitAntiV2IsNotImplementedByDefault;

    [Test]
    procedure TestBlitRectIsNotImplementedByDefault;

    [Test]
    procedure TestBlitMaskIsNotImplementedByDefault;

    [Test]
    procedure TestBlitHIsNotImplementedByDefault;
  end;

implementation

{ TTsHorizontalOnlyBlitter }

procedure TTsHorizontalOnlyBlitter.BlitH(const X, Y, Width: Cardinal);
begin
  FBlitted := FBlitted + Width;
end;

{ TTsBlitterTests }

procedure TTsBlitterTests.Setup;
begin
  FBlitter := TTsHorizontalOnlyBlitter.Create;
end;

procedure TTsBlitterTests.TearDown;
begin
  FBlitter.Free;
end;

procedure TTsBlitterTests.CallBlitH;
begin
  const Nothing = TTsNothingBlitter.Create;
  try
    Nothing.BlitH(0, 0, 1);
  finally
    Nothing.Free;
  end;
end;

procedure TTsBlitterTests.CallBlitAntiH;
begin
  var Alpha: TArray<Byte> := [255];
  var Runs: TArray<TTsAlphaRun> := [1, 0];

  FBlitter.BlitAntiH(0, 0, Alpha, Runs, 0);
end;

procedure TTsBlitterTests.CallBlitV;
begin
  FBlitter.BlitV(0, 0, 1, 255);
end;

procedure TTsBlitterTests.CallBlitAntiH2;
begin
  FBlitter.BlitAntiH2(0, 0, 1, 2);
end;

procedure TTsBlitterTests.CallBlitAntiV2;
begin
  FBlitter.BlitAntiV2(0, 0, 1, 2);
end;

procedure TTsBlitterTests.CallBlitRect;
begin
  FBlitter.BlitRect(TTsScreenIntRect.FromXYWHSafe(0, 0, 1, 1));
end;

procedure TTsBlitterTests.CallBlitMask;
begin
  var Mask: TTsBlitterMask;
  Mask.Image[0] := 255;
  Mask.Image[1] := 255;
  Mask.Bounds := TTsScreenIntRect.FromXYWHSafe(0, 0, 1, 1);
  Mask.RowBytes := 0;

  FBlitter.BlitMask(Mask, Mask.Bounds);
end;

procedure TTsBlitterTests.TestOverriddenMethodIsCalled;
begin
  FBlitter.BlitH(1, 2, 5);
  FBlitter.BlitH(1, 3, 2);

  Assert.AreEqual<Cardinal>(7, FBlitter.Blitted);
end;

procedure TTsBlitterTests.TestBlitHIsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitH, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitAntiHIsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitAntiH, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitVIsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitV, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitAntiH2IsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitAntiH2, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitAntiV2IsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitAntiV2, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitRectIsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitRect, EInvalidOpException);
end;

procedure TTsBlitterTests.TestBlitMaskIsNotImplementedByDefault;
begin
  Assert.WillRaise(CallBlitMask, EInvalidOpException);
end;

end.
