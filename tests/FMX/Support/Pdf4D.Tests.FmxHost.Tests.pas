// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Tests.FmxHost.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.UITypes,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost;

type
  // The spike of phase 4: an FMX form can be made and painted in the test process, on a scale that the test chooses, and its pixels can be
  // read back. When this does not hold, the FMX components cannot be tested the way the plan wants.
  [TestFixture]
  TFmxTestHostTests = class
  private
    FHost: TFmxTestHost;

    procedure PutSquare(const Left, Top, Size: Integer);

  public
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSquareIsPaintedAtScaleOne;
    [Test]
    procedure TestSquareIsPaintedAtScaleOnePointFive;
    [Test]
    procedure TestScaleCanChangeBetweenHosts;
  end;

implementation

uses
  FMX.Graphics,
  FMX.Objects,
  FMX.Types;

const
  ClientWidth = 100;
  ClientHeight = 80;
  SquareLeft = 10;
  SquareTop = 10;
  SquareSize = 50;
  SnapshotScaleTolerance = 0.001;

{ TFmxTestHostTests }

procedure TFmxTestHostTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TFmxTestHostTests.PutSquare(const Left, Top, Size: Integer);
begin
  const Square = TRectangle.Create(FHost.Form);
  Square.Parent := FHost.Content;
  Square.Align := TAlignLayout.None;
  Square.SetBounds(Left, Top, Size, Size);
  Square.Fill.Color := TAlphaColors.Red;
  Square.Stroke.Kind := TBrushKind.None;
end;

procedure TFmxTestHostTests.TestSquareIsPaintedAtScaleOne;
begin
  FHost := TFmxTestHost.Create(ClientWidth, ClientHeight, 1);
  PutSquare(SquareLeft, SquareTop, SquareSize);

  const Snapshot = FHost.Snapshot;
  try
    Assert.AreEqual(ClientWidth, Snapshot.Width, 'snapshot width in pixels');
    Assert.AreEqual(ClientHeight, Snapshot.Height, 'snapshot height in pixels');
    Assert.AreEqual(Double(1), Double(Snapshot.BitmapScale), SnapshotScaleTolerance);
    Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(TFmxTestHost.PixelAt(Snapshot, 30, 30)), 'inside the square');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(TFmxTestHost.PixelAt(Snapshot, 80, 70)), 'outside the square');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(TFmxTestHost.PixelAt(Snapshot, SquareLeft - 1, 30)), 'just left of the square');
    Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(TFmxTestHost.PixelAt(Snapshot, SquareLeft, 30)), 'first column of the square');
  finally
    Snapshot.Free;
  end;
end;

procedure TFmxTestHostTests.TestSquareIsPaintedAtScaleOnePointFive;
begin
  FHost := TFmxTestHost.Create(ClientWidth, ClientHeight, 1.5);
  PutSquare(SquareLeft, SquareTop, SquareSize);

  const Snapshot = FHost.Snapshot;
  try
    Assert.AreEqual(Round(ClientWidth * 1.5), Snapshot.Width, 'snapshot width in device pixels');
    Assert.AreEqual(Round(ClientHeight * 1.5), Snapshot.Height, 'snapshot height in device pixels');
    Assert.AreEqual(Double(1.5), Double(Snapshot.BitmapScale), SnapshotScaleTolerance);
    // The square covers the device pixels 15 to 89
    Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(TFmxTestHost.PixelAt(Snapshot, 45, 45)), 'inside the square');
    Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(TFmxTestHost.PixelAt(Snapshot, 15, 15)), 'first pixel of the square');
    Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(TFmxTestHost.PixelAt(Snapshot, 89, 89)), 'last pixel of the square');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(TFmxTestHost.PixelAt(Snapshot, 14, 45)), 'just left of the square');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(TFmxTestHost.PixelAt(Snapshot, 90, 45)), 'just right of the square');
    Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(TFmxTestHost.PixelAt(Snapshot, 130, 100)), 'outside the square');
  finally
    Snapshot.Free;
  end;
end;

procedure TFmxTestHostTests.TestScaleCanChangeBetweenHosts;
begin
  FHost := TFmxTestHost.Create(ClientWidth, ClientHeight, 2);
  var Snapshot := FHost.Snapshot;
  try
    Assert.AreEqual(2 * ClientWidth, Snapshot.Width);
  finally
    Snapshot.Free;
  end;
  FreeAndNil(FHost);

  FHost := TFmxTestHost.Create(ClientWidth, ClientHeight, 1);
  Snapshot := FHost.Snapshot;
  try
    Assert.AreEqual(ClientWidth, Snapshot.Width);
  finally
    Snapshot.Free;
  end;
end;

end.
