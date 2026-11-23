// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.Commands.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Commands,
  Pdf4D.Tests.TestDocument;

type
  [TestFixture]
  TPdfZoomTextTests = class
  public
    [Test]
    procedure TestItemsAreTheFitModesAndTheSteps;
    [Test]
    procedure TestIndexOf;
    [Test]
    procedure TestFormat;
    [Test]
    procedure TestTryParse;
    [Test]
    procedure TestTryParseRejects;
  end;

  [TestFixture]
  TPdfViewerCommandsTests = class
  private
    FBench: TDocumentBench;

    procedure OpenPages(const PageCount: Integer);

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNothingAppliesWhileClosed;
    [Test]
    procedure TestPageCommandsFollowTheCurrentPage;
    [Test]
    procedure TestViewCommandsNeedAPageView;
    [Test]
    procedure TestViewCommandsWorkOnThePageView;
    [Test]
    procedure TestFrameworkCommandsAreNotRunHere;
    [Test]
    procedure TestCommandThatDoesNotApplyRaises;
    [Test]
    procedure TestPageNumberField;
  end;

implementation

uses
  System.Types,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.Viewer.PageViewController,
  Pdf4D.Viewer.Painter.Interfaces,
  Pdf4D.Tests.RecordingPainter,
  Pdf4D.Tests.ViewerDocuments;

const
  Tolerance = 0.0001;
  PageWidth = 612;
  PageHeight = 792;
  ItemCount = 14;
  ViewportWidth = 800;
  ViewportHeight = 600;
  LogicalPixelsPerInch = 96;

{ TPdfZoomTextTests }

procedure TPdfZoomTextTests.TestItemsAreTheFitModesAndTheSteps;
begin
  const Items = TPdfZoomText.Items;
  Assert.AreEqual(ItemCount, Integer(Length(Items)));
  Assert.AreEqual(SZoomFitWidth, Items[0]);
  Assert.AreEqual(SZoomFitPage, Items[1]);
  Assert.AreEqual('10%', Items[2]);
  Assert.AreEqual('100%', Items[6]);
  Assert.AreEqual('800%', Items[High(Items)]);
end;

procedure TPdfZoomTextTests.TestIndexOf;
begin
  Assert.AreEqual(0, TPdfZoomText.IndexOf(TPdfZoomMode.FitWidth, 1));
  Assert.AreEqual(1, TPdfZoomText.IndexOf(TPdfZoomMode.FitPage, 1));
  Assert.AreEqual(7, TPdfZoomText.IndexOf(TPdfZoomMode.Factor, 1.25), '125%');
  Assert.AreEqual(-1, TPdfZoomText.IndexOf(TPdfZoomMode.Factor, 1.1), 'between the steps');
end;

procedure TPdfZoomTextTests.TestFormat;
begin
  Assert.AreEqual(SZoomFitWidth, TPdfZoomText.Format(TPdfZoomMode.FitWidth, 1));
  Assert.AreEqual(SZoomFitPage, TPdfZoomText.Format(TPdfZoomMode.FitPage, 1));
  Assert.AreEqual('110%', TPdfZoomText.Format(TPdfZoomMode.Factor, 1.1));
  Assert.AreEqual('333%', TPdfZoomText.Format(TPdfZoomMode.Factor, 3.333));
end;

procedure TPdfZoomTextTests.TestTryParse;
begin
  var Mode: TPdfZoomMode;
  var Zoom: Single;

  Assert.IsTrue(TPdfZoomText.TryParse(' 150 % ', Mode, Zoom));
  Assert.AreEqual(TPdfZoomMode.Factor, Mode);
  Assert.AreEqual(Double(1.5), Double(Zoom), Tolerance);

  Assert.IsTrue(TPdfZoomText.TryParse('80', Mode, Zoom), 'without a percent sign');
  Assert.AreEqual(Double(0.8), Double(Zoom), Tolerance);

  Assert.IsTrue(TPdfZoomText.TryParse(UpperCase(SZoomFitWidth), Mode, Zoom), 'the case does not count');
  Assert.AreEqual(TPdfZoomMode.FitWidth, Mode);

  Assert.IsTrue(TPdfZoomText.TryParse(SZoomFitPage, Mode, Zoom));
  Assert.AreEqual(TPdfZoomMode.FitPage, Mode);
end;

procedure TPdfZoomTextTests.TestTryParseRejects;
begin
  var Mode: TPdfZoomMode;
  var Zoom: Single;
  for var Text in ['', 'abc', '0', '-5%', '%'] do
  begin
    Assert.IsFalse(TPdfZoomText.TryParse(Text, Mode, Zoom), Text);
  end;
end;

{ TPdfViewerCommandsTests }

procedure TPdfViewerCommandsTests.Setup;
begin
  FBench := TDocumentBench.Create;
end;

procedure TPdfViewerCommandsTests.TearDown;
begin
  FreeAndNil(FBench);
end;

procedure TPdfViewerCommandsTests.OpenPages(const PageCount: Integer);
begin
  FBench.OpenData(TViewerDocuments.Pages(PageCount, PageWidth, PageHeight, 0));
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FBench.Document.State));
end;

procedure TPdfViewerCommandsTests.TestNothingAppliesWhileClosed;
begin
  for var Command := Low(TPdfViewerCommand) to High(TPdfViewerCommand) do
  begin
    Assert.IsFalse(TPdfViewerCommands.CanExecute(Command, FBench.Document, nil), 'a closed document');
    Assert.IsFalse(TPdfViewerCommands.CanExecute(Command, nil, nil), 'no document');
  end;
end;

procedure TPdfViewerCommandsTests.TestPageCommandsFollowTheCurrentPage;
begin
  OpenPages(3);
  const Document = FBench.Document;
  Assert.IsFalse(TPdfViewerCommands.CanExecute(TPdfViewerCommand.FirstPage, Document, nil), 'on the first page');
  Assert.IsFalse(TPdfViewerCommands.CanExecute(TPdfViewerCommand.PriorPage, Document, nil));
  Assert.IsTrue(TPdfViewerCommands.CanExecute(TPdfViewerCommand.NextPage, Document, nil));
  Assert.IsTrue(TPdfViewerCommands.CanExecute(TPdfViewerCommand.LastPage, Document, nil));
  Assert.IsTrue(TPdfViewerCommands.CanExecute(TPdfViewerCommand.Print, Document, nil), 'the document may be printed');
  Assert.IsTrue(TPdfViewerCommands.CanExecute(TPdfViewerCommand.Search, Document, nil));

  TPdfViewerCommands.Execute(TPdfViewerCommand.NextPage, Document, nil);
  Assert.AreEqual(1, Document.CurrentPage);
  TPdfViewerCommands.Execute(TPdfViewerCommand.LastPage, Document, nil);
  Assert.AreEqual(2, Document.CurrentPage);
  Assert.IsFalse(TPdfViewerCommands.CanExecute(TPdfViewerCommand.NextPage, Document, nil), 'on the last page');
  TPdfViewerCommands.Execute(TPdfViewerCommand.PriorPage, Document, nil);
  Assert.AreEqual(1, Document.CurrentPage);
  TPdfViewerCommands.Execute(TPdfViewerCommand.FirstPage, Document, nil);
  Assert.AreEqual(0, Document.CurrentPage);
end;

procedure TPdfViewerCommandsTests.TestViewCommandsNeedAPageView;
begin
  OpenPages(1);
  for var Command in [TPdfViewerCommand.ZoomIn, TPdfViewerCommand.ZoomOut, TPdfViewerCommand.ZoomFitWidth, TPdfViewerCommand.ZoomFitPage,
                      TPdfViewerCommand.RotateClockwise, TPdfViewerCommand.RotateCounterclockwise, TPdfViewerCommand.Copy] do
  begin
    Assert.IsFalse(TPdfViewerCommands.CanExecute(Command, FBench.Document, nil));
  end;
end;

procedure TPdfViewerCommandsTests.TestViewCommandsWorkOnThePageView;
begin
  OpenPages(2);
  const Host: IPdfViewHost = TRecordingHost.Create;
  const Controller = TPdfPageViewController.Create(Host);
  try
    Controller.Document := FBench.Document;
    Controller.SetViewport(TSize.Create(ViewportWidth, ViewportHeight), LogicalPixelsPerInch);
    Controller.Zoom := 1;

    Assert.IsTrue(TPdfViewerCommands.CanExecute(TPdfViewerCommand.ZoomIn, FBench.Document, Controller));
    TPdfViewerCommands.Execute(TPdfViewerCommand.ZoomIn, FBench.Document, Controller);
    Assert.AreEqual(Double(1.25), Double(Controller.Zoom), Tolerance, 'the next step');
    TPdfViewerCommands.Execute(TPdfViewerCommand.ZoomOut, FBench.Document, Controller);
    Assert.AreEqual(Double(1), Double(Controller.Zoom), Tolerance);

    Assert.IsFalse(TPdfViewerCommands.IsChecked(TPdfViewerCommand.ZoomFitPage, Controller));
    TPdfViewerCommands.Execute(TPdfViewerCommand.ZoomFitPage, FBench.Document, Controller);
    Assert.IsTrue(TPdfViewerCommands.IsChecked(TPdfViewerCommand.ZoomFitPage, Controller));
    Assert.IsFalse(TPdfViewerCommands.IsChecked(TPdfViewerCommand.ZoomFitWidth, Controller));

    TPdfViewerCommands.Execute(TPdfViewerCommand.RotateClockwise, FBench.Document, Controller);
    Assert.AreEqual(90, Controller.ViewRotation);
    TPdfViewerCommands.Execute(TPdfViewerCommand.RotateCounterclockwise, FBench.Document, Controller);
    Assert.AreEqual(0, Controller.ViewRotation);

    Assert.IsFalse(TPdfViewerCommands.CanExecute(TPdfViewerCommand.Copy, FBench.Document, Controller), 'nothing is selected');
  finally
    Controller.Free;
  end;
end;

procedure TPdfViewerCommandsTests.TestFrameworkCommandsAreNotRunHere;
begin
  OpenPages(1);
  for var Command in [TPdfViewerCommand.Copy, TPdfViewerCommand.Print, TPdfViewerCommand.Search] do
  begin
    Assert.WillRaise(
      procedure
      begin
        TPdfViewerCommands.Execute(Command, FBench.Document, nil);
      end,
      EPdfViewerException);
  end;
end;

procedure TPdfViewerCommandsTests.TestCommandThatDoesNotApplyRaises;
begin
  OpenPages(1);
  Assert.WillRaise(
    procedure
    begin
      TPdfViewerCommands.Execute(TPdfViewerCommand.NextPage, FBench.Document, nil);
    end,
    EInvalidOpException);
end;

procedure TPdfViewerCommandsTests.TestPageNumberField;
begin
  Assert.AreEqual('', TPdfViewerCommands.PageNumberText(FBench.Document), 'closed');
  Assert.AreEqual(Format(SPageCountOf, [0]), TPdfViewerCommands.PageCountText(FBench.Document));
  Assert.IsFalse(TPdfViewerCommands.TryGoToPageNumber(FBench.Document, '1'));

  OpenPages(3);
  Assert.AreEqual('1', TPdfViewerCommands.PageNumberText(FBench.Document));
  Assert.AreEqual(Format(SPageCountOf, [3]), TPdfViewerCommands.PageCountText(FBench.Document));

  Assert.IsTrue(TPdfViewerCommands.TryGoToPageNumber(FBench.Document, ' 2 '), 'spaces do not count');
  Assert.AreEqual(1, FBench.Document.CurrentPage);
  for var Text in ['0', '4', 'two', ''] do
  begin
    Assert.IsFalse(TPdfViewerCommands.TryGoToPageNumber(FBench.Document, Text), Text);
  end;
  Assert.AreEqual(1, FBench.Document.CurrentPage, 'a text that is no page changes nothing');
end;

end.
