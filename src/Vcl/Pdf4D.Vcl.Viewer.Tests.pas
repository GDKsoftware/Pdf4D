// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.Viewer.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Pdf4D.Common.Quad,
  Pdf4D.Api.TextLayout.Interfaces,
  Pdf4D.Viewer.PageText,
  Pdf4D.Viewer.Types,
  Pdf4D.Tests.VclHost,
  Pdf4D.Vcl.Viewer;

type
  [TestFixture]
  TPdf4DViewerTests = class
  private
    FHost: TVclTestHost;
    FViewer: TPdf4DViewer;
    FSelectedTexts: TList<string>;
    FHoverCount: Integer;
    FOpenErrorKinds: TList<TPdfOpenErrorKind>;
    FPasswordQuestions: Integer;

    procedure HandleTextSelected(Sender: TObject; const Selection: TPdfTextSelection);
    procedure HandleHoverChanged(Sender: TObject; const HasSegment: Boolean; const Segment: TPdfTextFragment);
    procedure HandleOpenError(Sender: TObject; const Kind: TPdfOpenErrorKind; const Message: string);

    procedure OpenData(const Data: TBytes);
    procedure OpenEncryptedFile;
    // Answers every question for the password with Password, or cancels when IsCancelled
    procedure AnswerPasswordWith(const Password: string; const IsCancelled: Boolean = False);
    function CenterOfWord(const Text: string; const Occurrence: Integer): TPoint;
    class function CountOf(const Owner: TComponent; const ComponentClass: TClass): Integer; static;

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
    procedure TestViewerStreamsToDfm;

    [Test]
    procedure TestOpenDocumentBeforeTheViewerHasAParent;

    [Test]
    procedure TestOpenedWhileTheViewerHasNoWindow;

    [Test]
    procedure TestViewerTakesNoOtherControls;
  end;

implementation

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Winapi.Windows,
  Pdf4D.Viewer.Document,
  Pdf4D.Vcl.PageView,
  Pdf4D.Vcl.Thumbnails,
  Pdf4D.Vcl.OutlineView,
  Pdf4D.Vcl.SearchBar,
  Pdf4D.Vcl.Toolbar,
  Pdf4D.Vcl.PrintDialog,
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

{ TPdf4DViewerTests }

procedure TPdf4DViewerTests.Setup;
begin
  FSelectedTexts := TList<string>.Create;
  FOpenErrorKinds := TList<TPdfOpenErrorKind>.Create;
  FHoverCount := 0;
  FPasswordQuestions := 0;

  FHost := TVclTestHost.Create(ViewWidth, ViewHeight);
  // The viewer has a page view of its own
  FHost.PageView.Visible := False;
  FHost.Document.OnOpenError := HandleOpenError;

  FViewer := TPdf4DViewer.Create(FHost.Form);
  FViewer.Parent := FHost.Form;
  FViewer.Align := TAlign.alClient;
  FViewer.Document := FHost.Document;
  FHost.Pump(1);
end;

procedure TPdf4DViewerTests.TearDown;
begin
  TPdf4DViewer.PasswordAsker := nil;
  TPdf4DPrintDialog.ModalRunner := nil;
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

procedure TPdf4DViewerTests.OpenData(const Data: TBytes);
begin
  Assert.IsTrue(FHost.Open(Data), 'the document opens: ' + FHost.OpenErrorMessage);
  FHost.Pump(1);
end;

procedure TPdf4DViewerTests.OpenEncryptedFile;
begin
  FHost.Document.FileName := TCorpus.PdfPath(EncryptedFile);
  FHost.Document.Open;
  FHost.WaitUntil(
    function: Boolean
    begin
      Result := FHost.Document.State in [TPdfDocumentState.Open, TPdfDocumentState.Failed];
    end);
  FHost.Pump(1);
end;

procedure TPdf4DViewerTests.AnswerPasswordWith(const Password: string; const IsCancelled: Boolean);
begin
  TPdf4DViewer.PasswordAsker :=
    function(out Answer: string): Boolean
    begin
      Inc(FPasswordQuestions);
      Answer := Password;
      Result := not IsCancelled;
    end;
end;

function TPdf4DViewerTests.CenterOfWord(const Text: string; const Occurrence: Integer): TPoint;
begin
  Assert.IsTrue(
    FHost.WaitUntil(
      function: Boolean
      var
        PageText: IPdfPageText;
      begin
        Result := FHost.Document.TryGetPageText(0, PageText);
      end),
    'the text of the first page arrives');

  var PageText: IPdfPageText;
  FHost.Document.TryGetPageText(0, PageText);
  var Seen := 0;
  for var Word in PageText.Words do
  begin
    if Word.Text = Text then
    begin
      if Seen = Occurrence then
      begin
        var Sum := TPoint.Zero;
        var Count := 0;
        for var Quad in Word.Quads do
        begin
          for var Corner in [Quad.P1, Quad.P2, Quad.P3, Quad.P4] do
          begin
            var ViewPoint: TPointF;
            Assert.IsTrue(FViewer.PageView.Controller.TryPageToViewport(0, Corner, ViewPoint), 'the page is laid out');
            Inc(Sum.X, Round(ViewPoint.X));
            Inc(Sum.Y, Round(ViewPoint.Y));
            Inc(Count);
          end;
        end;
        Exit(TPoint.Create(Sum.X div Count, Sum.Y div Count));
      end;
      Inc(Seen);
    end;
  end;
  Assert.Fail(Format('The word %s (%d) is not on the page', [Text, Occurrence]));
  Result := TPoint.Zero;
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

  Assert.IsTrue(FViewer.Toolbar.Visible, 'the toolbar');
  Assert.IsTrue(FViewer.SidePanel.Visible, 'the side panel');
  Assert.IsFalse(FViewer.SearchBar.Visible, 'the search bar is hidden until it is asked for');
  Assert.IsTrue(FViewer.PageView.Visible, 'the page view');
  Assert.IsTrue(FViewer.Toolbar.Top < FViewer.PageView.Top + FViewer.PageView.Height, 'the toolbar is above');
  Assert.IsTrue(FViewer.Toolbar.BoundsRect.Bottom <= FViewer.PageView.BoundsRect.Top + FViewer.Toolbar.Height, 'the page view is under the toolbar');
  Assert.IsTrue(FViewer.SidePanel.Left + FViewer.SidePanel.Width <= FViewer.PageView.Left, 'the side panel is at the left of the page view');
  Assert.IsTrue(FViewer.Toolbar.Top + FViewer.Toolbar.Height <= FViewer.SidePanel.Top, 'the side panel is under the toolbar');
  Assert.AreEqual('Pages', FViewer.TabSheetPages.Caption);
  Assert.AreEqual('Bookmarks', FViewer.TabSheetBookmarks.Caption);
  Assert.IsTrue(FViewer.Thumbnails.Parent = FViewer.TabSheetPages, 'the thumbnails are on the Pages tab');
  Assert.IsTrue(FViewer.OutlineView.Parent = FViewer.TabSheetBookmarks, 'the outline is on the Bookmarks tab');
  Assert.IsTrue(FViewer.PageView.Width > FViewer.SidePanel.Width, 'the page view fills the rest');
end;

procedure TPdf4DViewerTests.TestOptionsHideParts;
begin
  OpenData(TViewerDocuments.Outlined);
  FViewer.SearchBar.Visible := True;
  Assert.IsNotNull(FViewer.Toolbar.ButtonPrint, 'the print button is there by default');
  Assert.IsNotNull(FViewer.Toolbar.ButtonSearch, 'the search button is there by default');

  FViewer.Options := [TPdf4DViewerOption.Toolbar];
  FHost.Pump(1);

  Assert.IsTrue(FViewer.Toolbar.Visible, 'the toolbar stays');
  Assert.IsFalse(FViewer.SidePanel.Visible, 'no side panel');
  Assert.IsFalse(FViewer.SearchBar.Visible, 'no search bar');
  Assert.IsNull(FViewer.Toolbar.ButtonPrint, 'no print button without Print');
  Assert.IsNull(FViewer.Toolbar.ButtonSearch, 'no search button without Search');
  Assert.IsNotNull(FViewer.Toolbar.ButtonNext, 'the other buttons stay');

  FViewer.Options := [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Print];
  FHost.Pump(1);
  Assert.IsNotNull(FViewer.Toolbar.ButtonPrint, 'Print brings the print button back');
  Assert.IsNull(FViewer.Toolbar.ButtonSearch);

  FViewer.Options := [TPdf4DViewerOption.Thumbnails];
  FHost.Pump(1);
  Assert.IsFalse(FViewer.Toolbar.Visible, 'no toolbar');
  Assert.IsTrue(FViewer.SidePanel.Visible, 'the side panel with the thumbnails');
  Assert.IsTrue(FViewer.TabSheetPages.TabVisible);
  Assert.IsFalse(FViewer.TabSheetBookmarks.TabVisible, 'no bookmarks without Outline');

  FViewer.Options := [TPdf4DViewerOption.Outline];
  FHost.Pump(1);
  Assert.IsTrue(FViewer.SidePanel.Visible, 'the side panel with the outline');
  Assert.IsFalse(FViewer.TabSheetPages.TabVisible, 'no pages without Thumbnails');
  Assert.IsTrue(FViewer.TabSheetBookmarks.TabVisible);

  FViewer.Options := [];
  FHost.Pump(1);
  Assert.IsFalse(FViewer.SidePanel.Visible);
  Assert.IsTrue(FViewer.PageView.Visible, 'the page view stays');
end;

procedure TPdf4DViewerTests.TestOutlineTabHiddenWithoutOutline;
begin
  OpenData(TViewerDocuments.Invoice);
  Assert.IsTrue(FViewer.TabSheetPages.TabVisible, 'the pages tab');
  Assert.IsFalse(FViewer.TabSheetBookmarks.TabVisible, 'no outline, no bookmarks tab');

  OpenData(TViewerDocuments.Outlined);
  Assert.IsTrue(FViewer.TabSheetBookmarks.TabVisible, 'an outline brings the bookmarks tab');

  FHost.Document.Close;
  FHost.Pump(1);
  Assert.IsFalse(FViewer.TabSheetBookmarks.TabVisible, 'a closed document has no outline');

  FViewer.Options := [TPdf4DViewerOption.Outline];
  OpenData(TViewerDocuments.Invoice);
  Assert.IsFalse(FViewer.SidePanel.Visible, 'only the outline, and there is none: no side panel');
  OpenData(TViewerDocuments.Outlined);
  Assert.IsTrue(FViewer.SidePanel.Visible, 'the document has an outline');
end;

procedure TPdf4DViewerTests.TestSidePanelWidth;
begin
  Assert.AreEqual(DefaultSidePanelWidth, FViewer.SidePanelWidth);
  Assert.AreEqual(DefaultSidePanelWidth, FViewer.SidePanel.Width);

  FViewer.SidePanelWidth := 240;

  Assert.AreEqual(240, FViewer.SidePanel.Width);
  Assert.AreEqual(240, FViewer.SidePanelWidth);
end;

procedure TPdf4DViewerTests.TestCtrlFShowsSearchBar;
begin
  OpenData(TViewerDocuments.Invoice);
  Assert.IsFalse(FViewer.SearchBar.Visible);

  FViewer.PageView.SetFocus;
  FHost.PressShortCutOn(FViewer.PageView, Ord('F'), [ssCtrl]);
  FHost.Pump(1);

  Assert.IsTrue(FViewer.SearchBar.Visible, 'Ctrl+F shows the search bar');
  Assert.IsTrue(FViewer.SearchBar.EditQuery.Focused, 'the cursor is in the query field');
end;

procedure TPdf4DViewerTests.TestShortCutsBelongToTheFocusInsideTheViewer;
begin
  OpenData(TViewerDocuments.Invoice);
  var Runs := 0;
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Runs);
      Result := mrCancel;
    end;

  const Outside = TEdit.Create(FHost.Form);
  Outside.Parent := FHost.Form;
  Outside.SetFocus;
  FHost.PressShortCutOn(Outside, Ord('F'), [ssCtrl]);
  FHost.PressShortCutOn(Outside, Ord('P'), [ssCtrl]);
  FHost.Pump(1);
  Assert.IsFalse(FViewer.SearchBar.Visible, 'Ctrl+F outside the viewer is not for the viewer');
  Assert.AreEqual(0, Runs, 'Ctrl+P outside the viewer is not for the viewer');

  FViewer.PageView.SetFocus;
  FHost.PressShortCutOn(FViewer.PageView, Ord('P'), [ssCtrl]);
  FHost.Pump(1);
  Assert.AreEqual(1, Runs, 'Ctrl+P inside the viewer shows the print dialog');

  FViewer.Options := FViewer.Options - [TPdf4DViewerOption.Print];
  FViewer.PageView.SetFocus;
  FHost.PressShortCutOn(FViewer.PageView, Ord('P'), [ssCtrl]);
  FHost.Pump(1);
  Assert.AreEqual(1, Runs, 'Ctrl+P does nothing without the print option');
end;

procedure TPdf4DViewerTests.TestCtrlFDoesNothingWithoutSearchOption;
begin
  FViewer.Options := [TPdf4DViewerOption.Toolbar];
  OpenData(TViewerDocuments.Invoice);

  FViewer.PageView.SetFocus;
  FHost.PressShortCutOn(FViewer.PageView, Ord('F'), [ssCtrl]);
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
  FHost.ClickOn(FViewer.PageView, Center.X, Center.Y);

  Assert.AreEqual<Integer>(1, FSelectedTexts.Count, 'one selection');
  Assert.AreEqual(InvoiceNumber, FSelectedTexts[0]);
  Assert.IsTrue(FHoverCount > 0, 'the hover is forwarded');

  FViewer.OnTextSelected := nil;
  Assert.IsFalse(Assigned(FViewer.PageView.OnTextSelected), 'nil takes the handler away');
end;

procedure TPdf4DViewerTests.TestPrintButtonUsesThePrintDialog;
begin
  Assert.IsTrue(FViewer.Toolbar.PrintDialog = FViewer.PrintDialog, 'the toolbar prints with the dialog of the viewer');
  OpenData(TViewerDocuments.Invoice);

  var Runs := 0;
  TPdf4DPrintDialog.ModalRunner :=
    function(Form: TPdf4DPrintDialogForm): TModalResult
    begin
      Inc(Runs);
      Result := mrCancel;
    end;
  FViewer.Toolbar.ButtonPrint.Click;

  Assert.AreEqual(1, Runs, 'the print dialog is shown');
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
  FHost.WaitUntil(
    function: Boolean
    begin
      Result := FHost.Document.State = TPdfDocumentState.Failed;
    end);
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

procedure TPdf4DViewerTests.TestViewerStreamsToDfm;
begin
  System.Classes.RegisterClass(TPdf4DViewer);

  // As on a form of the designer: the form is the root of the stream, and the parts of the viewer are not on it
  const Source = TForm.CreateNew(nil);
  try
    const SourceViewer = TPdf4DViewer.Create(Source);
    SourceViewer.Name := 'Viewer';
    SourceViewer.Parent := Source;
    SourceViewer.Options := [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Outline];
    SourceViewer.SidePanelWidth := 230;
    SourceViewer.AskPassword := False;

    const Stream = TMemoryStream.Create;
    try
      Stream.WriteComponentRes('Form', Source);
      Stream.Position := 0;

      const Target = TForm.CreateNew(nil);
      try
        Stream.ReadComponentRes(Target);

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
        Assert.AreEqual(1, CountOf(TargetViewer, TPanel), 'the side panel is made once');
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
    Viewer.OutlineView.HandleNeeded;

    Assert.AreEqual(3, Viewer.OutlineView.Items.Count, 'the outline is shown');
    Assert.IsTrue(Viewer.TabSheetBookmarks.TabVisible, 'the bookmarks tab is there');
  finally
    Viewer.Free;
  end;
end;

// A form that is made but not shown yet opens a document: the parts of its viewer hear Opened without a window
procedure TPdf4DViewerTests.TestOpenedWhileTheViewerHasNoWindow;
begin
  FViewer.Document := nil;
  const Viewer = TPdf4DViewer.Create(nil);
  try
    Viewer.Document := FHost.Document;
    OpenData(TViewerDocuments.Outlined);
    FHost.Pump(1);

    Viewer.Parent := FHost.Form;
    FHost.Pump(1);
    Viewer.OutlineView.HandleNeeded;
    Assert.AreEqual(3, Viewer.OutlineView.Items.Count, 'the outline is shown once the viewer has a window');
  finally
    Viewer.Free;
  end;
end;

procedure TPdf4DViewerTests.TestViewerTakesNoOtherControls;
begin
  Assert.IsFalse(csAcceptsControls in FViewer.ControlStyle, 'a designer drops no controls into the viewer');
  Assert.IsFalse(csSetCaption in FViewer.ControlStyle, 'the viewer has no caption of its name');
end;

end.
