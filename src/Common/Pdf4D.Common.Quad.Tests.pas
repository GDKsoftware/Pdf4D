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
