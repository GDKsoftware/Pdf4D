// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Content.GraphicsState.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TGraphicsStateTests = class
  public
    [Test]
    procedure TestNewStateHasPdfDefaults;

    [Test]
    procedure TestCloneIsIndependent;

    [Test]
    procedure TestCloneCopiesTextMatrices;

    [Test]
    procedure TestTextMatricesAreNullUntilSet;

    [Test]
    [TestCase('Fill', '0,True,False,False')]
    [TestCase('Stroke', '1,False,True,False')]
    [TestCase('FillStroke', '2,True,True,False')]
    [TestCase('Neither', '3,False,False,False')]
    [TestCase('FillClip', '4,True,False,True')]
    [TestCase('StrokeClip', '5,False,True,True')]
    [TestCase('FillStrokeClip', '6,True,True,True')]
    [TestCase('NeitherClip', '7,False,False,True')]
    procedure TestRenderingMode(const Value: Integer; const IsFill, IsStroke, IsClip: Boolean);

    [Test]
    [TestCase('Negative', '-1')]
    [TestCase('TooBig', '8')]
    procedure TestRenderingModeOutOfRangeIsRejected(const Value: Integer);
  end;

implementation

uses
  Pdf4D.Common.Matrix,
  Pdf4D.Content.GraphicsState;

{ TGraphicsStateTests }

procedure TGraphicsStateTests.TestNewStateHasPdfDefaults;
begin
  const State = TPDGraphicsState.Create;
  try
    Assert.IsTrue(State.CurrentTransformationMatrix.IsEqual(TPdfMatrix.Identity));
    Assert.AreEqual(Double(100), Double(State.TextState.HorizontalScaling), 0.0001);
    Assert.AreEqual(Double(0), Double(State.TextState.CharacterSpacing), 0.0001);
    Assert.AreEqual(Double(0), Double(State.TextState.WordSpacing), 0.0001);
    Assert.AreEqual(Double(0), Double(State.TextState.Leading), 0.0001);
    Assert.AreEqual(Double(0), Double(State.TextState.Rise), 0.0001);
    Assert.AreEqual(Double(0), Double(State.TextState.FontSize), 0.0001);
    Assert.IsTrue(State.TextState.RenderingMode = TRenderingMode.Fill);
    Assert.IsTrue(State.TextState.Knockout);
    Assert.IsNull(State.TextState.Font);
  finally
    State.Free;
  end;
end;

procedure TGraphicsStateTests.TestCloneIsIndependent;
begin
  const State = TPDGraphicsState.Create;
  try
    State.CurrentTransformationMatrix := TPdfMatrix.Create(2, 0, 0, 2, 10, 20);
    State.TextState.FontSize := 12;
    State.TextState.WordSpacing := 3;

    const Copy = State.Clone;
    try
      Copy.CurrentTransformationMatrix := TPdfMatrix.Create(1, 0, 0, 1, 5, 5);
      Copy.TextState.FontSize := 99;
      Copy.TextState.WordSpacing := 7;

      Assert.AreEqual(Double(12), Double(State.TextState.FontSize), 0.0001);
      Assert.AreEqual(Double(3), Double(State.TextState.WordSpacing), 0.0001);
      Assert.AreEqual(Double(10), Double(State.CurrentTransformationMatrix.TranslateX), 0.0001);
      Assert.AreEqual(Double(99), Double(Copy.TextState.FontSize), 0.0001);
    finally
      Copy.Free;
    end;

    const Second = State.Clone;
    try
      Assert.AreEqual(Double(12), Double(Second.TextState.FontSize), 0.0001, 'a clone starts with the values of the original');
      Assert.AreEqual(Double(2), Double(Second.CurrentTransformationMatrix.ScaleX), 0.0001);
    finally
      Second.Free;
    end;
  finally
    State.Free;
  end;
end;

procedure TGraphicsStateTests.TestCloneCopiesTextMatrices;
begin
  const State = TPDGraphicsState.Create;
  try
    State.SetTextMatrix(TPdfMatrix.Create(1, 0, 0, 1, 7, 8));
    State.SetTextLineMatrix(TPdfMatrix.Create(1, 0, 0, 1, 9, 10));

    const Copy = State.Clone;
    try
      Copy.SetTextMatrix(TPdfMatrix.Create(1, 0, 0, 1, 70, 80));
      Copy.ClearTextLineMatrix;

      var Matrix: TPdfMatrix;
      Assert.IsTrue(State.TryGetTextMatrix(Matrix));
      Assert.AreEqual(Double(7), Double(Matrix.TranslateX), 0.0001);
      Assert.IsTrue(State.TryGetTextLineMatrix(Matrix));
      Assert.AreEqual(Double(9), Double(Matrix.TranslateX), 0.0001);
      Assert.IsFalse(Copy.TryGetTextLineMatrix(Matrix));
      Assert.IsTrue(Copy.TryGetTextMatrix(Matrix));
      Assert.AreEqual(Double(70), Double(Matrix.TranslateX), 0.0001);
    finally
      Copy.Free;
    end;
  finally
    State.Free;
  end;
end;

procedure TGraphicsStateTests.TestTextMatricesAreNullUntilSet;
begin
  const State = TPDGraphicsState.Create;
  try
    var Matrix: TPdfMatrix;
    Assert.IsFalse(State.TryGetTextMatrix(Matrix));
    Assert.IsFalse(State.TryGetTextLineMatrix(Matrix));

    State.SetTextMatrix(TPdfMatrix.Identity);
    Assert.IsTrue(State.TryGetTextMatrix(Matrix));
    State.ClearTextMatrix;
    Assert.IsFalse(State.TryGetTextMatrix(Matrix));
  finally
    State.Free;
  end;
end;

procedure TGraphicsStateTests.TestRenderingMode(const Value: Integer; const IsFill, IsStroke, IsClip: Boolean);
begin
  var Mode: TRenderingMode;
  Assert.IsTrue(TRenderingMode.TryFromInt(Value, Mode));

  Assert.AreEqual(Value, Mode.IntValue);
  Assert.AreEqual(IsFill, Mode.IsFill);
  Assert.AreEqual(IsStroke, Mode.IsStroke);
  Assert.AreEqual(IsClip, Mode.IsClip);
end;

procedure TGraphicsStateTests.TestRenderingModeOutOfRangeIsRejected(const Value: Integer);
begin
  var Mode: TRenderingMode;

  Assert.IsFalse(TRenderingMode.TryFromInt(Value, Mode));
end;

end.
