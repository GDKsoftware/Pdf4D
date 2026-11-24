// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Viewer.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.Types,
  System.UITypes,
  FMX.Controls,
  FMX.Layouts,
  FMX.StdCtrls,
  FMX.Types,
  DUnitX.TestFramework,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.FmxHost,
  Pdf4D.FMX.PrintDialog,
  Pdf4D.FMX.Viewer;

type
  // Gives the tests the click of a button, as a press of the mouse does
  TButtonCracker = class(TSpeedButton);

  [TestFixture]
  TPdf4DViewerTests = class
  private
    FHost: TFmxTestHost;
    FViewer: TPdf4DViewer;
    FSelectedTexts: TList<string>;
    FHoverCount: Integer;
    FOpenErrorKinds: TList<TPdfOpenErrorKind>;
    FPasswordQuestions: Integer;
    FPasswordAnswer: string;
    FIsPasswordCancelled: Boolean;
    FPrintRuns: Integer;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);

    // The answer of the password question of the test
    function AnswerPassword(out Password: string): Boolean;
    function CancelPrintDialog(const Form: TPdf4DPrintDialogForm): TModalResult;
    function IsDocumentSettled: Boolean;
    function IsPageViewQuiet: Boolean;

    procedure OpenData(const Data: TBytes);
    procedure OpenEncryptedFile;
    // Answers every question for the password with Password, or cancels when IsCancelled
    procedure AnswerPasswordWith(const Password: string; const IsCancelled: Boolean = False);
    // The center of a word on the first page, in logical units of the page view
    function CenterOfWord(const Text: string; const Occurrence: Integer): TPointF;
    class function CountOf(const Owner: TComponent; const ComponentClass: TClass): Integer; static;
    // Whether the control is in the container, directly or through the content of the container
    class function IsInside(const Control: TControl; const Container: TFmxObject): Boolean; static;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAllPartsShareDocument;

    [Test]
    procedure TestPartsAreLaidOut;

    [Test]
    procedure TestOptionsHideParts;

    [Test]
    procedure TestOutlineTabHiddenWithoutOutline;

    [Test]
    procedure TestSidePanelWidth;

    [Test]
    procedure TestCtrlFShowsSearchBar;

    [Test]
    procedure TestShortCutsBelongToTheFocusInsideTheViewer;

    [Test]
    procedure TestCtrlFDoesNothingWithoutSearchOption;

    [Test]
    procedure TestEventsAreForwarded;

    [Test]
    procedure TestPrintButtonUsesThePrintDialog;

    [Test]
    procedure TestPasswordIsAsked;

    [Test]
    procedure TestPasswordIsAskedThreeTimesAtMost;

    [Test]
    procedure TestPasswordCancelStops;

    [Test]
    procedure TestPasswordNotAskedWhenOff;

    [Test]
    procedure TestViewerStreamsToFmx;

    [Test]
    procedure TestOpenDocumentBeforeTheViewerHasAParent;
  end;

implementation

uses
  FMX.Forms,
  FMX.TabControl,
  FMX.Edit,
  Pdf4D.Viewer.Document,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.Thumbnails,
  Pdf4D.FMX.OutlineView,
  Pdf4D.FMX.SearchBar,
  Pdf4D.FMX.Toolbar,
  Pdf4D.Tests.Corpus,
  Pdf4D.Tests.ViewerDocuments;

const
  ViewWidth = 900;
  ViewHeight = 700;
  InvoiceNumber = '2024-0815';
  EncryptedFile = 'generated/encrypted/aes-128-user.pdf';
  WrongPassword = 'not the password';
  DefaultSidePanelWidth = 180;
  PasswordAttempts = 3;
  TearDownPumpMs = 200;

{ TPdf4DViewerTests }

procedure TPdf4DViewerTests.Setup;
begin
  FSelectedTexts := TList<string>.Create;
  FOpenErrorKinds := TList<TPdfOpenErrorKind>.Create;
  FHoverCount := 0;
  FPasswordQuestions := 0;
  FPrintRuns := 0;

  FHost := TFmxTestHost.Create(ViewWidth, ViewHeight);
  FHost.Document.OnOpenError := HandleOpenError;

  FViewer := TPdf4DViewer.Create(FHost.Form);
  FViewer.Parent := FHost.Form;
  FViewer.Align := TAlignLayout.Client;
  FViewer.Document := FHost.Document;
  FHost.Pump(1);
end;


procedure TPdf4DViewerTests.TearDown;
begin
  TPdf4DViewer.PasswordAsker := nil;
  TPdf4DPrintDialog.ModalRunner := nil;
  // Letting go of the document cancels the requests of the parts; what is on its way comes back through the queue of the main thread and
  // has to arrive before the memory check of the program
  FViewer.Document := nil;
  Assert.IsTrue(FHost.WaitUntil(IsPageViewQuiet), 'the page view has no tiles outstanding');
  FHost.Pump(TearDownPumpMs);
  FreeAndNil(FHost);
  FOpenErrorKinds.Free;
  FSelectedTexts.Free;
end;

procedure TPdf4DViewerTests.HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FSelectedTexts.Add(Selection.Text);
end;

procedure TPdf4DViewerTests.HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
begin
  Inc(FHoverCount);
end;

procedure TPdf4DViewerTests.HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);
begin
  FOpenErrorKinds.Add(Kind);
end;

function TPdf4DViewerTests.AnswerPassword(out Password: string): Boolean;
begin
  Inc(FPasswordQuestions);
  Password := FPasswordAnswer;
  Result := not FIsPasswordCancelled;
end;

function TPdf4DViewerTests.CancelPrintDialog(const Form: TPdf4DPrintDialogForm): TModalResult;
begin
  Inc(FPrintRuns);
  Result := mrCancel;
end;

function TPdf4DViewerTests.IsDocumentSettled: Boolean;
begin
  Result := FHost.Document.State in [TPdfDocumentState.Open, TPdfDocumentState.Failed];
end;

function TPdf4DViewerTests.IsPageViewQuiet: Boolean;
begin
  Result := FViewer.PageView.Controller.PendingTileCount = 0;
end;

procedure TPdf4DViewerTests.OpenData(const Data: TBytes);
begin
  Assert.IsTrue(FHost.Open(Data), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);
end;

procedure TPdf4DViewerTests.OpenEncryptedFile;
begin
  FHost.Document.FileName := TCorpus.PdfPath(EncryptedFile);
  FHost.Document.Open;
  FHost.WaitUntil(IsDocumentSettled);
  FHost.Pump(1);
end;

procedure TPdf4DViewerTests.AnswerPasswordWith(const Password: string; const IsCancelled: Boolean);
begin
  FPasswordAnswer := Password;
  FIsPasswordCancelled := IsCancelled;
  TPdf4DViewer.PasswordAsker := AnswerPassword;
end;

function TPdf4DViewerTests.CenterOfWord(const Text: string; const Occurrence: Integer): TPointF;
begin
  Assert.IsTrue(FHost.WaitForPageText(0), 'the text of the first page arrives');

  var PageText: IPdfPageText;
  Assert.IsTrue(FHost.Document.TryGetPageText(0, PageText), 'the text is known');
  var Seen := 0;
  for var Word in PageText.Words do
  begin
    if Word.Text <> Text then
    begin
      Continue;
    end;

    if Seen = Occurrence then
    begin
      var Sum := TPointF.Create(0, 0);
      var Count := 0;
      for var Quad in Word.Quads do
      begin
        for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
        begin
          var ViewPoint: TPointF;
          Assert.IsTrue(FViewer.PageView.Controller.TryPageToViewport(0, Corner, ViewPoint), 'the page is laid out');
          Sum := Sum + ViewPoint;
          Inc(Count);
        end;
      end;
      // The viewport is in device pixels
      Exit(TPointF.Create(Sum.X / Count / FHost.Scale, Sum.Y / Count / FHost.Scale));
    end;
    Inc(Seen);
  end;
  Assert.Fail(Format('The word %s (%d) is not on the page', [Text, Occurrence]));
  Result := TPointF.Zero;
end;

class function TPdf4DViewerTests.CountOf(const Owner: TComponent; const ComponentClass: TClass): Integer;
begin
  Result := 0;
  for var Index := 0 to Owner.ComponentCount - 1 do
  begin
    if Owner.Components[Index].InheritsFrom(ComponentClass) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TPdf4DViewerTests.IsInside(const Control: TControl; const Container: TFmxObject): Boolean;
begin
  var Current: TFmxObject := Control.Parent;
  while Assigned(Current) and (Current <> Container) do
  begin
    Current := Current.Parent;
  end;
  Result := Assigned(Current);
end;

procedure TPdf4DViewerTests.TestAllPartsShareDocument;
begin
  Assert.IsTrue(FViewer.Document = FHost.Document, 'the viewer');
  Assert.IsTrue(FViewer.PageView.Document = FHost.Document, 'the page view');
  Assert.IsTrue(FViewer.Toolbar.Document = FHost.Document, 'the toolbar');
  Assert.IsTrue(FViewer.Thumbnails.Document = FHost.Document, 'the thumbnails');
  Assert.IsTrue(FViewer.OutlineView.Document = FHost.Document, 'the outline view');
  Assert.IsTrue(FViewer.SearchBar.Document = FHost.Document, 'the search bar');
  Assert.IsTrue(FViewer.PrintDialog.Document = FHost.Document, 'the print dialog');
  Assert.IsTrue(FViewer.Toolbar.PageView = FViewer.PageView, 'the toolbar works on the page view of the viewer');
  Assert.IsTrue(FViewer.Toolbar.SearchBar = FViewer.SearchBar, 'the toolbar works on the search bar of the viewer');
  Assert.IsTrue(FViewer.Toolbar.PrintDialog = FViewer.PrintDialog, 'the toolbar prints with the dialog of the viewer');

  FViewer.Document := nil;

  Assert.IsNull(FViewer.PageView.Document, 'the page view lets go');
  Assert.IsNull(FViewer.Toolbar.Document, 'the toolbar lets go');
  Assert.IsNull(FViewer.Thumbnails.Document, 'the thumbnails let go');
  Assert.IsNull(FViewer.OutlineView.Document, 'the outline view lets go');
  Assert.IsNull(FViewer.SearchBar.Document, 'the search bar lets go');
  Assert.IsNull(FViewer.PrintDialog.Document, 'the print dialog lets go');
end;

procedure TPdf4DViewerTests.TestPartsAreLaidOut;
begin
  OpenData(TViewerDocuments.Invoice);
  FHost.Pump(1);

  Assert.IsTrue(FViewer.Toolbar.Visible, 'the toolbar');
  Assert.IsTrue(FViewer.TabControl.Visible, 'the side panel');
  Assert.IsFalse(FViewer.SearchBar.Visible, 'the search bar is hidden until it is asked for');
  Assert.IsTrue(FViewer.PageView.Visible, 'the page view');
  Assert.IsTrue(FViewer.Toolbar.Position.Y + FViewer.Toolbar.Height <= FViewer.TabControl.Position.Y + 0.5, 'the side panel is under the toolbar');
  Assert.IsTrue(FViewer.Toolbar.Position.Y + FViewer.Toolbar.Height <= FViewer.PageView.Position.Y + 0.5, 'the page view is under the toolbar');
  Assert.IsTrue(FViewer.TabControl.Position.X + FViewer.TabControl.Width <= FViewer.PageView.Position.X + 0.5,
                'the side panel is at the left of the page view');
  Assert.AreEqual('Pages', FViewer.TabItemPages.Text);
  Assert.AreEqual('Bookmarks', FViewer.TabItemBookmarks.Text);
  Assert.IsTrue(IsInside(FViewer.Thumbnails, FViewer.TabItemPages), 'the thumbnails are on the Pages tab');
  Assert.IsTrue(IsInside(FViewer.OutlineView, FViewer.TabItemBookmarks), 'the outline is on the Bookmarks tab');
  Assert.IsTrue(FViewer.PageView.Width > FViewer.TabControl.Width, 'the page view fills the rest');
  Assert.IsTrue(FViewer.Splitter.Visible, 'the splitter');
end;

procedure TPdf4DViewerTests.TestOptionsHideParts;
begin
  OpenData(TViewerDocuments.Outlined);
  FViewer.SearchBar.Visible := True;
  Assert.IsNotNull(FViewer.Toolbar.ButtonPrint, 'the print button is there by default');
  Assert.IsNotNull(FViewer.Toolbar.ButtonSearch, 'the search button is there by default');

  FViewer.Options := [TPdf4DViewerOption.Toolbar];

  Assert.IsTrue(FViewer.Toolbar.Visible, 'the toolbar stays');
  Assert.IsFalse(FViewer.TabControl.Visible, 'no side panel');
  Assert.IsFalse(FViewer.Splitter.Visible, 'no splitter');
  Assert.IsFalse(FViewer.SearchBar.Visible, 'no search bar');
  Assert.IsNull(FViewer.Toolbar.ButtonPrint, 'no print button without Print');
  Assert.IsNull(FViewer.Toolbar.ButtonSearch, 'no search button without Search');
  Assert.IsNotNull(FViewer.Toolbar.ButtonNext, 'the other buttons stay');

  FViewer.Options := [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Print];
  Assert.IsNotNull(FViewer.Toolbar.ButtonPrint, 'Print brings the print button back');
  Assert.IsNull(FViewer.Toolbar.ButtonSearch);

  FViewer.Options := [TPdf4DViewerOption.Thumbnails];
  Assert.IsFalse(FViewer.Toolbar.Visible, 'no toolbar');
  Assert.IsTrue(FViewer.TabControl.Visible, 'the side panel with the thumbnails');
  Assert.IsTrue(FViewer.TabItemPages.Visible);
  Assert.IsFalse(FViewer.TabItemBookmarks.Visible, 'no bookmarks without Outline');

  FViewer.Options := [TPdf4DViewerOption.Outline];
  Assert.IsTrue(FViewer.TabControl.Visible, 'the side panel with the outline');
  Assert.IsFalse(FViewer.TabItemPages.Visible, 'no pages without Thumbnails');
  Assert.IsTrue(FViewer.TabItemBookmarks.Visible);
  Assert.IsTrue(FViewer.TabControl.ActiveTab = FViewer.TabItemBookmarks, 'the visible tab is the active one');

  FViewer.Options := [];
  Assert.IsFalse(FViewer.TabControl.Visible);
  Assert.IsTrue(FViewer.PageView.Visible, 'the page view stays');
end;

procedure TPdf4DViewerTests.TestOutlineTabHiddenWithoutOutline;
begin
  OpenData(TViewerDocuments.Invoice);
  Assert.IsTrue(FViewer.TabItemPages.Visible, 'the pages tab');
  Assert.IsFalse(FViewer.TabItemBookmarks.Visible, 'no outline, no bookmarks tab');

  OpenData(TViewerDocuments.Outlined);
  Assert.IsTrue(FViewer.TabItemBookmarks.Visible, 'an outline brings the bookmarks tab');

  FHost.Document.Close;
  FHost.Pump(1);
  Assert.IsFalse(FViewer.TabItemBookmarks.Visible, 'a closed document has no outline');

  FViewer.Options := [TPdf4DViewerOption.Outline];
  OpenData(TViewerDocuments.Invoice);
  Assert.IsFalse(FViewer.TabControl.Visible, 'only the outline, and there is none: no side panel');
  OpenData(TViewerDocuments.Outlined);
  Assert.IsTrue(FViewer.TabControl.Visible, 'the document has an outline');
end;

procedure TPdf4DViewerTests.TestSidePanelWidth;
begin
  Assert.AreEqual(DefaultSidePanelWidth, FViewer.SidePanelWidth);
  Assert.AreEqual<Single>(DefaultSidePanelWidth, FViewer.TabControl.Width);

  FViewer.SidePanelWidth := 240;

  Assert.AreEqual<Single>(240, FViewer.TabControl.Width);
  Assert.AreEqual(240, FViewer.SidePanelWidth);
end;

procedure TPdf4DViewerTests.TestCtrlFShowsSearchBar;
begin
  OpenData(TViewerDocuments.Invoice);
  Assert.IsFalse(FViewer.SearchBar.Visible);

  FHost.PressKeyOn(FViewer.PageView, vkF, [ssCtrl]);
  FHost.Pump(1);

  Assert.IsTrue(FViewer.SearchBar.Visible, 'Ctrl+F shows the search bar');
  Assert.IsTrue(FViewer.SearchBar.EditQuery.IsFocused, 'the cursor is in the query field');
end;

procedure TPdf4DViewerTests.TestShortCutsBelongToTheFocusInsideTheViewer;
begin
  OpenData(TViewerDocuments.Invoice);
  TPdf4DPrintDialog.ModalRunner := CancelPrintDialog;

  const Outside = TEdit.Create(FHost.Form);
  Outside.Parent := FHost.Form;
  FHost.PressKeyOn(Outside, vkF, [ssCtrl]);
  FHost.PressKeyOn(Outside, vkP, [ssCtrl]);
  FHost.Pump(1);
  Assert.IsFalse(FViewer.SearchBar.Visible, 'Ctrl+F outside the viewer is not for the viewer');
  Assert.AreEqual(0, FPrintRuns, 'Ctrl+P outside the viewer is not for the viewer');

  FHost.PressKeyOn(FViewer.PageView, vkP, [ssCtrl]);
  FHost.Pump(1);
  Assert.AreEqual(1, FPrintRuns, 'Ctrl+P inside the viewer shows the print dialog');

  FViewer.Options := FViewer.Options - [TPdf4DViewerOption.Print];
  FHost.PressKeyOn(FViewer.PageView, vkP, [ssCtrl]);
  FHost.Pump(1);
  Assert.AreEqual(1, FPrintRuns, 'Ctrl+P does nothing without the print option');

  FViewer.Options := FViewer.Options + [TPdf4DViewerOption.Print];
  FHost.PressKeyOn(FViewer.PageView, vkP, [ssCtrl]);
  FHost.Pump(1);
  Assert.AreEqual(2, FPrintRuns, 'the print option brings Ctrl+P back');
end;

procedure TPdf4DViewerTests.TestCtrlFDoesNothingWithoutSearchOption;
begin
  FViewer.Options := [TPdf4DViewerOption.Toolbar];
  OpenData(TViewerDocuments.Invoice);

  FHost.PressKeyOn(FViewer.PageView, vkF, [ssCtrl]);
  FHost.Pump(1);

  Assert.IsFalse(FViewer.SearchBar.Visible);
end;

procedure TPdf4DViewerTests.TestEventsAreForwarded;
begin
  FViewer.OnTextSelected := HandleTextSelected;
  FViewer.OnHoverChanged := HandleHoverChanged;
  Assert.IsTrue(Assigned(FViewer.PageView.OnTextSelected), 'the page view gets the handler');
  Assert.IsTrue(Assigned(FViewer.OnTextSelected), 'and the viewer gives it back');

  OpenData(TViewerDocuments.Invoice);
  // On the second line the number is a segment of its own
  const Center = CenterOfWord(InvoiceNumber, 1);
  FViewer.PageView.HandleMouseMove(Center);
  FViewer.PageView.HandleMouseDown(Center);
  FViewer.PageView.HandleMouseUp(Center);

  Assert.AreEqual<Integer>(1, FSelectedTexts.Count, 'one selection');
  Assert.AreEqual(InvoiceNumber, FSelectedTexts[0]);
  Assert.IsTrue(FHoverCount > 0, 'the hover is forwarded');

  FViewer.OnTextSelected := nil;
  Assert.IsFalse(Assigned(FViewer.PageView.OnTextSelected), 'nil takes the handler away');
end;

procedure TPdf4DViewerTests.TestPrintButtonUsesThePrintDialog;
begin
  OpenData(TViewerDocuments.Invoice);
  TPdf4DPrintDialog.ModalRunner := CancelPrintDialog;

  TButtonCracker(FViewer.Toolbar.ButtonPrint).Click;

  Assert.AreEqual(1, FPrintRuns, 'the print dialog is shown');
end;

procedure TPdf4DViewerTests.TestPasswordIsAsked;
begin
  AnswerPasswordWith(TCorpus.PasswordFor(EncryptedFile));

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FHost.Document.State), 'the document opens with the password of the user');
  Assert.AreEqual(1, FPasswordQuestions, 'asked once');
  Assert.AreEqual<Integer>(0, FOpenErrorKinds.Count, 'nobody hears of an error');
end;

procedure TPdf4DViewerTests.TestPasswordIsAskedThreeTimesAtMost;
begin
  AnswerPasswordWith(WrongPassword);

  OpenEncryptedFile;

  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FHost.Document.State));
  Assert.AreEqual(PasswordAttempts, FPasswordQuestions, 'asked three times');
  Assert.AreEqual<Integer>(1, FOpenErrorKinds.Count, 'the failure is told once');
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(FOpenErrorKinds[0]));

  // A new open starts afresh
  FHost.Document.Open;
  FHost.WaitUntil(IsDocumentSettled);
  FHost.Pump(1);
  Assert.AreEqual(2 * PasswordAttempts, FPasswordQuestions, 'three more questions');
end;

procedure TPdf4DViewerTests.TestPasswordCancelStops;
begin
  AnswerPasswordWith('', True);

  OpenEncryptedFile;

  Assert.AreEqual(1, FPasswordQuestions, 'asked once');
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FHost.Document.State));
  Assert.AreEqual<Integer>(1, FOpenErrorKinds.Count);
  Assert.AreEqual(Ord(TPdfOpenErrorKind.InvalidPassword), Ord(FOpenErrorKinds[0]));
end;

procedure TPdf4DViewerTests.TestPasswordNotAskedWhenOff;
begin
  AnswerPasswordWith(TCorpus.PasswordFor(EncryptedFile));
  FViewer.AskPassword := False;

  OpenEncryptedFile;

  Assert.AreEqual(0, FPasswordQuestions, 'not asked');
  Assert.AreEqual(Ord(TPdfDocumentState.Failed), Ord(FHost.Document.State));
  Assert.AreEqual<Integer>(1, FOpenErrorKinds.Count);
end;

procedure TPdf4DViewerTests.TestViewerStreamsToFmx;
begin
  System.Classes.RegisterClass(TPdf4DViewer);

  // As on a form of the designer: a container is the root of the stream, and the parts of the viewer are not in it. A layout is used in place
  // of a form because a form makes a window, and the memory check of the test program counts the windows that FMX keeps back.
  const Source = TLayout.Create(nil);
  try
    const SourceViewer = TPdf4DViewer.Create(Source);
    SourceViewer.Name := 'Viewer';
    SourceViewer.Parent := Source;
    SourceViewer.Options := [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Outline];
    SourceViewer.SidePanelWidth := 230;
    SourceViewer.AskPassword := False;

    const Stream = TMemoryStream.Create;
    try
      Stream.WriteComponent(Source);
      Stream.Position := 0;

      const Target = TLayout.Create(nil);
      try
        Stream.ReadComponent(Target);

        const TargetViewer = Target.FindComponent('Viewer') as TPdf4DViewer;
        Assert.IsNotNull(TargetViewer, 'the viewer is read');
        Assert.IsTrue(TargetViewer.Options = [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Outline], 'the options');
        Assert.AreEqual(230, TargetViewer.SidePanelWidth, 'the width of the side panel');
        Assert.IsFalse(TargetViewer.AskPassword, 'AskPassword');

        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DPageView), 'one page view');
        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DToolbar), 'one toolbar');
        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DThumbnails), 'one thumbnails control');
        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DOutlineView), 'one outline view');
        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DSearchBar), 'one search bar');
        Assert.AreEqual(1, CountOf(TargetViewer, TPdf4DPrintDialog), 'one print dialog');
        Assert.AreEqual(1, CountOf(TargetViewer, TSplitter), 'one splitter');
        Assert.AreEqual(1, CountOf(TargetViewer, TTabControl), 'the side panel is made once');
        Assert.AreEqual(2, CountOf(TargetViewer, TTabItem), 'two tabs');
      finally
        Target.Free;
      end;
    finally
      Stream.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TPdf4DViewerTests.TestOpenDocumentBeforeTheViewerHasAParent;
begin
  OpenData(TViewerDocuments.Outlined);
  const Viewer = TPdf4DViewer.Create(nil);
  try
    Viewer.Document := FHost.Document;
    Viewer.Parent := FHost.Form;
    FHost.Pump(1);

    Assert.IsTrue(Viewer.OutlineView.Count > 0, 'the outline is shown');
    Assert.IsTrue(Viewer.TabItemBookmarks.Visible, 'the bookmarks tab is there');
  finally
    Viewer.Free;
  end;
end;

end.
