// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.Quad.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad;

type
  [TestFixture]
  TPdfQuadTests = class
  public
    [Test]
    procedure TestBoundsOfRotatedQuad;

    [Test]
    procedure TestExtendKeepsStartOfFirstAndEndOfSecond;

    [Test]
    procedure TestExtendUsesTheLargerHeight;

    [Test]
    procedure TestExtendEnclosesBothHeights;

    [Test]
    procedure TestExtendBelowSelfAndRotated;

    [Test]
    procedure TestExtendOfHugeQuadsDoesNotRaise;

    [Test]
    procedure TestIsFiniteFalseForNaN;
  end;

implementation

uses
  System.Math;

const
  Tolerance = 0.001;

{ TPdfQuadTests }

procedure TPdfQuadTests.TestBoundsOfRotatedQuad;
begin
  const Quad = TPdfQuad.Create(TPointF.Create(102, 700), TPointF.Create(102, 706), TPointF.Create(92, 706), TPointF.Create(92, 700));

  const Bounds = Quad.Bounds;

  Assert.AreEqual(Double(92), Double(Bounds.Left), Tolerance);
  Assert.AreEqual(Double(102), Double(Bounds.Right), Tolerance);
  Assert.AreEqual(Double(700), Double(Bounds.Top), Tolerance);
  Assert.AreEqual(Double(706), Double(Bounds.Bottom), Tolerance);
end;

procedure TPdfQuadTests.TestExtendKeepsStartOfFirstAndEndOfSecond;
begin
  const First = TPdfQuad.Create(TPointF.Create(10, 0), TPointF.Create(20, 0), TPointF.Create(20, 10), TPointF.Create(10, 10));
  const Second = TPdfQuad.Create(TPointF.Create(20, 0), TPointF.Create(35, 0), TPointF.Create(35, 10), TPointF.Create(20, 10));

  const Union = First.Extend(Second);

  Assert.AreEqual(Double(10), Double(Union.P1.X), Tolerance);
  Assert.AreEqual(Double(35), Double(Union.P2.X), Tolerance);
  Assert.AreEqual(Double(35), Double(Union.P3.X), Tolerance);
  Assert.AreEqual(Double(10), Double(Union.P4.X), Tolerance);
  Assert.AreEqual(Double(10), Double(Union.P3.Y - Union.P2.Y), Tolerance);
end;

procedure TPdfQuadTests.TestExtendUsesTheLargerHeight;
begin
  const First = TPdfQuad.Create(TPointF.Create(10, 0), TPointF.Create(20, 0), TPointF.Create(20, 10), TPointF.Create(10, 10));
  const Second = TPdfQuad.Create(TPointF.Create(20, 0), TPointF.Create(35, 0), TPointF.Create(35, 14), TPointF.Create(20, 14));

  const Union = First.Extend(Second);

  Assert.AreEqual(Double(14), Double(Union.P4.Y - Union.P1.Y), Tolerance);
  Assert.AreEqual(Double(14), Double(Union.P3.Y - Union.P2.Y), Tolerance);
end;

procedure TPdfQuadTests.TestExtendEnclosesBothHeights;
begin
  const Small = TPdfQuad.Create(TPointF.Create(10, -5), TPointF.Create(20, -5), TPointF.Create(20, 7), TPointF.Create(10, 7));
  const Large = TPdfQuad.Create(TPointF.Create(20, -3), TPointF.Create(38, -3), TPointF.Create(38, 15), TPointF.Create(20, 15));

  const Union = Small.Extend(Large);

  Assert.AreEqual(Double(-5), Double(Union.P1.Y), Tolerance);
  Assert.AreEqual(Double(-5), Double(Union.P2.Y), Tolerance);
  Assert.AreEqual(Double(15), Double(Union.P3.Y), Tolerance);
  Assert.AreEqual(Double(15), Double(Union.P4.Y), Tolerance);
  Assert.AreEqual(Double(10), Double(Union.P1.X), Tolerance);
  Assert.AreEqual(Double(38), Double(Union.P2.X), Tolerance);
end;

procedure TPdfQuadTests.TestExtendBelowSelfAndRotated;
begin
  const First = TPdfQuad.Create(TPointF.Create(10, 0), TPointF.Create(20, 0), TPointF.Create(20, 10), TPointF.Create(10, 10));
  const Second = TPdfQuad.Create(TPointF.Create(20, -4), TPointF.Create(30, -4), TPointF.Create(30, 8), TPointF.Create(20, 8));
  const RotatedFirst = TPdfQuad.Create(TPointF.Create(0, 10), TPointF.Create(0, 20), TPointF.Create(-10, 20), TPointF.Create(-10, 10));
  const RotatedSecond = TPdfQuad.Create(TPointF.Create(4, 20), TPointF.Create(4, 30), TPointF.Create(-8, 30), TPointF.Create(-8, 20));

  const Union = First.Extend(Second);
  const RotatedUnion = RotatedFirst.Extend(RotatedSecond);

  Assert.AreEqual(Double(-4), Double(Union.P1.Y), Tolerance);
  Assert.AreEqual(Double(-4), Double(Union.P2.Y), Tolerance);
  Assert.AreEqual(Double(10), Double(Union.P3.Y), Tolerance);
  Assert.AreEqual(Double(10), Double(Union.P4.Y), Tolerance);
  Assert.AreEqual(Double(4), Double(RotatedUnion.P1.X), Tolerance);
  Assert.AreEqual(Double(-10), Double(RotatedUnion.P4.X), Tolerance);
  Assert.AreEqual(Double(30), Double(RotatedUnion.P2.Y), Tolerance);
end;

procedure TPdfQuadTests.TestExtendOfHugeQuadsDoesNotRaise;
begin
  const Huge: Single = 1E30;
  const First = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(Huge, 0), TPointF.Create(Huge, Huge), TPointF.Create(0, Huge));
  const Second = TPdfQuad.Create(TPointF.Create(Huge, 0), TPointF.Create(Huge, 0), TPointF.Create(Huge, Huge), TPointF.Create(Huge, Huge));
  var Union: TPdfQuad;

  Assert.WillNotRaise(
    procedure
    begin
      Union := First.Extend(Second);
    end);

  Assert.IsTrue(Union.IsFinite);
end;

procedure TPdfQuadTests.TestIsFiniteFalseForNaN;
begin
  const Finite = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(1, 0), TPointF.Create(1, 1), TPointF.Create(0, 1));
  const NotANumber = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(NaN, 0), TPointF.Create(1, 1), TPointF.Create(0, 1));
  const Infinite = TPdfQuad.Create(TPointF.Create(0, 0), TPointF.Create(1, 0), TPointF.Create(1, Infinity), TPointF.Create(0, 1));

  Assert.IsTrue(Finite.IsFinite);
  Assert.IsFalse(NotANumber.IsFinite);
  Assert.IsFalse(Infinite.IsFinite);
end;

end.
