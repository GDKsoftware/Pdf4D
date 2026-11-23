// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Overlay.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TOverlayListTests = class
  private
    FBench: TDocumentBench;

    class function Square(const Left: Single): TPdfQuad; static;
    function AddOverlay(const PageIndex: Integer): Integer;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAddReturnsIncreasingIds;
    [Test]
    procedure TestOnPageFilters;
    [Test]
    procedure TestItemsKeepWhatWasAdded;
    [Test]
    procedure TestRemoveUnknownIdIsIgnored;
    [Test]
    procedure TestRemoveTakesTheOverlayAway;
    [Test]
    procedure TestAddWhileClosedRaises;
    [Test]
    procedure TestAddOutsidePagesRaises;
    [Test]
    procedure TestAddWithoutQuadsRaises;
    [Test]
    procedure TestAddNonFiniteQuadRaises;
    [Test]
    procedure TestChangesNotifyLinks;
    [Test]
    procedure TestCloseClearsOverlays;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.Math,
  Pdf4D.Tests.ViewerDocuments;

const
  Red = $66FF0000;

{ TOverlayListTests }

procedure TOverlayListTests.Setup;
begin
  FBench := TDocumentBench.Create;
end;

procedure TOverlayListTests.TearDown;
begin
  FBench.Free;
end;

class function TOverlayListTests.Square(const Left: Single): TPdfQuad;
begin
  Result := TPdfQuad.Create(TPointF.Create(Left, 100), TPointF.Create(Left + 50, 100),
                            TPointF.Create(Left + 50, 120), TPointF.Create(Left, 120));
end;

function TOverlayListTests.AddOverlay(const PageIndex: Integer): Integer;
begin
  Result := FBench.Document.Overlays.Add(PageIndex, [Square(10)], TPdfOverlayStyle.Fill, Red);
end;

procedure TOverlayListTests.TestAddReturnsIncreasingIds;
begin
  FBench.OpenData(TViewerDocuments.Invoice);

  const First = AddOverlay(0);
  const Second = AddOverlay(0);
  FBench.Document.Overlays.Remove(Second);
  const Third = AddOverlay(1);

  Assert.IsTrue(Second > First);
  Assert.IsTrue(Third > Second, 'an Id is not used again');
end;

procedure TOverlayListTests.TestOnPageFilters;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  const OnFirst = AddOverlay(0);
  const OnSecond = AddOverlay(1);
  const AlsoOnFirst = AddOverlay(0);

  const FirstPage = FBench.Document.Overlays.OnPage(0);
  const SecondPage = FBench.Document.Overlays.OnPage(1);

  Assert.AreEqual(2, Integer(Length(FirstPage)));
  Assert.AreEqual(OnFirst, FirstPage[0].Id);
  Assert.AreEqual(AlsoOnFirst, FirstPage[1].Id);
  Assert.AreEqual(1, Integer(Length(SecondPage)));
  Assert.AreEqual(OnSecond, SecondPage[0].Id);
  Assert.AreEqual(3, Integer(Length(FBench.Document.Overlays.Items)));
end;

procedure TOverlayListTests.TestItemsKeepWhatWasAdded;
begin
  FBench.OpenData(TViewerDocuments.Invoice);

  const Id = FBench.Document.Overlays.Add(1, [Square(10), Square(80)], TPdfOverlayStyle.Ellipse, $99112233);

  const Items = FBench.Document.Overlays.Items;
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual(Id, Items[0].Id);
  Assert.AreEqual(1, Items[0].PageIndex);
  Assert.AreEqual(Ord(TPdfOverlayStyle.Ellipse), Ord(Items[0].Style));
  Assert.AreEqual<Cardinal>($99112233, Items[0].Color);
  Assert.AreEqual(2, Integer(Length(Items[0].Quads)));
  Assert.AreEqual<Single>(80, Items[0].Quads[1].P1.X);
end;

procedure TOverlayListTests.TestRemoveUnknownIdIsIgnored;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  AddOverlay(0);
  FBench.Recorder.Reset;

  FBench.Document.Overlays.Remove(12345);

  Assert.AreEqual(1, Integer(Length(FBench.Document.Overlays.Items)));
  Assert.AreEqual('', FBench.Recorder.Describe);
end;

procedure TOverlayListTests.TestRemoveTakesTheOverlayAway;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  const Keep = AddOverlay(0);
  const Drop = AddOverlay(0);

  FBench.Document.Overlays.Remove(Drop);

  const Items = FBench.Document.Overlays.Items;
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual(Keep, Items[0].Id);
end;

procedure TOverlayListTests.TestAddWhileClosedRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      AddOverlay(0);
    end,
    EInvalidOpException);
end;

procedure TOverlayListTests.TestAddOutsidePagesRaises;
begin
  FBench.OpenData(TViewerDocuments.Invoice);

  Assert.WillRaise(
    procedure
    begin
      AddOverlay(2);
    end,
    EArgumentOutOfRangeException);
  Assert.WillRaise(
    procedure
    begin
      AddOverlay(-1);
    end,
    EArgumentOutOfRangeException);
  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
end;

procedure TOverlayListTests.TestAddWithoutQuadsRaises;
begin
  FBench.OpenData(TViewerDocuments.Invoice);

  Assert.WillRaise(
    procedure
    begin
      FBench.Document.Overlays.Add(0, nil, TPdfOverlayStyle.Fill, Red);
    end,
    EArgumentException);
end;

procedure TOverlayListTests.TestAddNonFiniteQuadRaises;
begin
  FBench.OpenData(TViewerDocuments.Invoice);

  Assert.WillRaise(
    procedure
    begin
      FBench.Document.Overlays.Add(0, [Square(10), Square(NaN)], TPdfOverlayStyle.Fill, Red);
    end,
    EArgumentException);
  Assert.WillRaise(
    procedure
    begin
      FBench.Document.Overlays.Add(0, [Square(Infinity)], TPdfOverlayStyle.Fill, Red);
    end,
    EArgumentException);
  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
end;

procedure TOverlayListTests.TestChangesNotifyLinks;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  FBench.Recorder.Reset;

  const Id = AddOverlay(0);
  Assert.AreEqual('Overlays', FBench.Recorder.Describe);

  FBench.Document.Overlays.Remove(Id);
  Assert.AreEqual('Overlays,Overlays', FBench.Recorder.Describe);

  FBench.Document.Overlays.Clear;
  Assert.AreEqual('Overlays,Overlays', FBench.Recorder.Describe, 'clearing nothing changes nothing');

  AddOverlay(1);
  FBench.Document.Overlays.Clear;
  Assert.AreEqual('Overlays,Overlays,Overlays,Overlays', FBench.Recorder.Describe);
end;

procedure TOverlayListTests.TestCloseClearsOverlays;
begin
  FBench.OpenData(TViewerDocuments.Invoice);
  AddOverlay(0);
  AddOverlay(1);
  FBench.Recorder.Reset;

  FBench.Document.Close;

  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
  Assert.AreEqual('Closed', FBench.Recorder.Describe);

  FBench.OpenData(TViewerDocuments.Invoice);
  Assert.AreEqual(0, Integer(Length(FBench.Document.Overlays.Items)));
end;

end.
