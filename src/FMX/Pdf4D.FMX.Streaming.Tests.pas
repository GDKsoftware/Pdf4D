// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Streaming.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  FMX.Forms,
  DUnitX.TestFramework,
  Pdf4D.FMX.Document;

type
  // A document that the designer would have made: its component state says it is being designed
  TDesignDocument = class(TPdf4DDocument)
  public
    procedure MakeDesigned;
  end;

  [TestFixture]
  TPdf4DFmxStreamingTests = class
  private
    FForm: TForm;

    class function ActionClasses: TArray<TComponentClass>; static;
    class function ComponentClasses: TArray<TComponentClass>; static;
    // Makes one of the class on FForm with the name of the class without its T
    function MakeComponent(const ComponentClass: TComponentClass): TComponent;
    // The properties that the form streams for the component, with their values as text
    function StreamedProperties(const Component: TComponent): TStringList;
    // Writes FForm and reads it back into a new form that the caller owns
    function RoundTrip: TForm;
    procedure ChangeAllComponents;
    procedure CheckAllComponents(const Target: TForm);
    procedure ChangeAction(const Action: TComponent; const Index: Integer);
    procedure CheckAction(const Source, Target: TComponent; const Index: Integer);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestAllComponentsStreamRoundTrip;

    [Test]
    procedure TestDefaultsAreNotStreamed;

    [Test]
    procedure TestComponentsWorkInDesignState;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.Actions,
  System.UITypes,
  FMX.ActnList,
  FMX.Controls,
  FMX.Types,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Print,
  Pdf4D.FMX.Actions,
  Pdf4D.FMX.Backend.Skia,
  Pdf4D.FMX.OutlineView,
  Pdf4D.FMX.PageView,
  Pdf4D.FMX.PrintDialog,
  Pdf4D.FMX.SearchBar,
  Pdf4D.FMX.Thumbnails,
  Pdf4D.FMX.Toolbar,
  Pdf4D.FMX.Viewer,
  Pdf4D.Tests.ViewerDocuments;

const
  SomeFileName = 'C:\documents\invoice.pdf';
  SomePassword = 'open sesame';

type
  // Opens the protected state of a component for the test of the design state
  TDesignAccess = class(TComponent);

{ TDesignDocument }

procedure TDesignDocument.MakeDesigned;
begin
  TDesignAccess(Self).SetDesigning(True, False);
end;

{ TPdf4DFmxStreamingTests }

class function TPdf4DFmxStreamingTests.ActionClasses: TArray<TComponentClass>;
begin
  Result := [
    TPdf4DZoomInAction, TPdf4DZoomOutAction, TPdf4DZoomFitWidthAction, TPdf4DZoomFitPageAction, TPdf4DRotateClockwiseAction,
    TPdf4DRotateCounterclockwiseAction, TPdf4DCopyAction, TPdf4DFirstPageAction, TPdf4DPriorPageAction, TPdf4DNextPageAction,
    TPdf4DLastPageAction, TPdf4DPrintAction, TPdf4DSearchAction];
end;

class function TPdf4DFmxStreamingTests.ComponentClasses: TArray<TComponentClass>;
begin
  Result := [
    TPdf4DDocument, TPdf4DSkiaBackend, TPdf4DPageView, TPdf4DThumbnails, TPdf4DOutlineView, TPdf4DSearchBar, TPdf4DToolbar,
    TPdf4DViewer, TPdf4DPrintDialog];
end;

procedure TPdf4DFmxStreamingTests.Setup;
begin
  FForm := TForm.CreateNew(nil);
  for var ComponentClass in ComponentClasses + ActionClasses do
  begin
    System.Classes.RegisterClass(ComponentClass);
  end;
end;

procedure TPdf4DFmxStreamingTests.TearDown;
begin
  FreeAndNil(FForm);
end;

function TPdf4DFmxStreamingTests.MakeComponent(const ComponentClass: TComponentClass): TComponent;
begin
  Result := ComponentClass.Create(FForm);
  Result.Name := Copy(ComponentClass.ClassName, 2, MaxInt);
  if Result is TControl then
  begin
    TControl(Result).Parent := FForm;
  end;
end;

function TPdf4DFmxStreamingTests.StreamedProperties(const Component: TComponent): TStringList;
begin
  const Binary = TMemoryStream.Create;
  const Text = TMemoryStream.Create;
  try
    Binary.WriteComponent(Component);
    Binary.Position := 0;
    ObjectBinaryToText(Binary, Text);
    Text.Position := 0;

    const Lines = TStringList.Create;
    try
      Lines.LoadFromStream(Text);
      Result := TStringList.Create;
      // The properties of the component itself sit one level in; the lines of nested objects sit deeper
      for var Line in Lines do
      begin
        if (Length(Line) > 2) and (Line[1] = ' ') and (Line[2] = ' ') and (Line[3] <> ' ') and (Pos(' = ', Line) > 0)
          and (not Line.TrimLeft.StartsWith('object ')) then
        begin
          Result.Add(Line.Trim);
        end;
      end;
    finally
      Lines.Free;
    end;
  finally
    Text.Free;
    Binary.Free;
  end;
end;

function TPdf4DFmxStreamingTests.RoundTrip: TForm;
begin
  const Stream = TMemoryStream.Create;
  try
    Stream.WriteComponentRes('Form', FForm);
    Stream.Position := 0;
    Result := TForm.CreateNew(nil);
    try
      Stream.ReadComponentRes(Result);
    except
      Result.Free;
      raise;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdf4DFmxStreamingTests.ChangeAction(const Action: TComponent; const Index: Integer);
begin
  const Target = TCustomAction(Action);
  Target.Text := 'Text ' + IntToStr(Index);
  Target.Hint := 'Hint ' + IntToStr(Index);
  Target.ImageIndex := 20 + Index;
  Target.ShortCut := 4096 + 65 + Index;
  Target.Enabled := False;
  Target.Visible := False;
end;

procedure TPdf4DFmxStreamingTests.CheckAction(const Source, Target: TComponent; const Index: Integer);
begin
  const Name = Source.Name;
  const Read = TCustomAction(Target);
  Assert.AreEqual('Text ' + IntToStr(Index), Read.Text, Name + ' Text');
  Assert.AreEqual('Hint ' + IntToStr(Index), Read.Hint, Name + ' Hint');
  Assert.AreEqual(20 + Index, Integer(Read.ImageIndex), Name + ' ImageIndex');
  Assert.AreEqual(4096 + 65 + Index, Integer(Read.ShortCut), Name + ' ShortCut');
  Assert.IsFalse(Read.Enabled, Name + ' Enabled');
  Assert.IsFalse(Read.Visible, Name + ' Visible');
end;

procedure TPdf4DFmxStreamingTests.ChangeAllComponents;
begin
  const Backend = FForm.FindComponent('Pdf4DSkiaBackend') as TPdf4DSkiaBackend;
  const Document = FForm.FindComponent('Pdf4DDocument') as TPdf4DDocument;
  Document.FileName := SomeFileName;
  Document.Password := SomePassword;
  Document.Backend := Backend;
  Document.IgnorePermissions := True;
  Document.PageTextCacheCount := 5;

  const PageView = FForm.FindComponent('Pdf4DPageView') as TPdf4DPageView;
  PageView.Document := Document;
  PageView.ZoomMode := TPdfZoomMode.Factor;
  PageView.Zoom := 1.5;
  PageView.ViewRotation := 90;
  PageView.ScrollMode := TPdfScrollMode.SinglePage;
  PageView.HoverEnabled := False;
  PageView.SelectionEnabled := False;
  PageView.FollowInternalLinks := False;
  PageView.HoverColor := TAlphaColors.Red;
  PageView.SelectionColor := TAlphaColors.Lime;
  PageView.SearchHitColor := TAlphaColors.Blue;
  PageView.CurrentSearchHitColor := TAlphaColors.Yellow;
  PageView.BackgroundColor := TAlphaColors.White;
  PageView.Align := TAlignLayout.Left;
  PageView.Anchors := [TAnchorKind.akLeft, TAnchorKind.akBottom];
  PageView.TabStop := False;
  PageView.Visible := False;

  const Thumbnails = FForm.FindComponent('Pdf4DThumbnails') as TPdf4DThumbnails;
  Thumbnails.Document := Document;
  Thumbnails.ThumbnailWidth := 77;
  Thumbnails.SelectedColor := TAlphaColors.Red;
  Thumbnails.BackgroundColor := TAlphaColors.White;
  Thumbnails.Align := TAlignLayout.Right;
  Thumbnails.Visible := False;

  const OutlineView = FForm.FindComponent('Pdf4DOutlineView') as TPdf4DOutlineView;
  OutlineView.Document := Document;
  OutlineView.Align := TAlignLayout.Top;
  OutlineView.Visible := False;

  const SearchBar = FForm.FindComponent('Pdf4DSearchBar') as TPdf4DSearchBar;
  SearchBar.Document := Document;
  SearchBar.Align := TAlignLayout.Bottom;
  SearchBar.Visible := False;

  const PrintDialog = FForm.FindComponent('Pdf4DPrintDialog') as TPdf4DPrintDialog;
  PrintDialog.Document := Document;
  PrintDialog.RangeKind := TPdfPrintRangeKind.Pages;
  PrintDialog.Scale := TPdfPrintScale.ActualSize;
  PrintDialog.Copies := 3;
  PrintDialog.MaxDpi := 150;
  PrintDialog.ShowProgress := False;

  const Toolbar = FForm.FindComponent('Pdf4DToolbar') as TPdf4DToolbar;
  Toolbar.Document := Document;
  Toolbar.PageView := PageView;
  Toolbar.SearchBar := SearchBar;
  Toolbar.PrintDialog := PrintDialog;
  Toolbar.Buttons := [TPdf4DToolbarButton.Zoom, TPdf4DToolbarButton.Print];

  const Viewer = FForm.FindComponent('Pdf4DViewer') as TPdf4DViewer;
  Viewer.Document := Document;
  Viewer.Options := [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Outline];
  Viewer.SidePanelWidth := 222;
  Viewer.AskPassword := False;
  Viewer.Align := TAlignLayout.None;
  Viewer.Visible := False;

  var Index := 0;
  for var ActionClass in ActionClasses do
  begin
    const Action = FForm.FindComponent(Copy(ActionClass.ClassName, 2, MaxInt));
    ChangeAction(Action, Index);
    if Action is TPdf4DPageViewAction then
    begin
      TPdf4DPageViewAction(Action).PageView := PageView;
    end
    else if Action is TPdf4DDocumentAction then
    begin
      TPdf4DDocumentAction(Action).Document := Document;
    end;
    if Action is TPdf4DPrintAction then
    begin
      TPdf4DPrintAction(Action).PrintDialog := PrintDialog;
    end;
    if Action is TPdf4DSearchAction then
    begin
      TPdf4DSearchAction(Action).SearchBar := SearchBar;
    end;
    Inc(Index);
  end;
end;

procedure TPdf4DFmxStreamingTests.CheckAllComponents(const Target: TForm);
begin
  const Backend = Target.FindComponent('Pdf4DSkiaBackend') as TPdf4DSkiaBackend;
  Assert.IsNotNull(Backend, 'the backend is read');

  const Document = Target.FindComponent('Pdf4DDocument') as TPdf4DDocument;
  Assert.IsNotNull(Document, 'the document is read');
  Assert.AreEqual(SomeFileName, Document.FileName, 'FileName');
  Assert.AreEqual(SomePassword, Document.Password, 'Password');
  Assert.AreSame(Backend, Document.Backend, 'the backend link');
  Assert.IsTrue(Document.IgnorePermissions, 'IgnorePermissions');
  Assert.AreEqual(5, Document.PageTextCacheCount, 'PageTextCacheCount');

  const PageView = Target.FindComponent('Pdf4DPageView') as TPdf4DPageView;
  Assert.IsNotNull(PageView, 'the page view is read');
  Assert.AreSame(Document, PageView.Document, 'the page view link');
  Assert.IsTrue(PageView.ZoomMode = TPdfZoomMode.Factor, 'ZoomMode');
  Assert.AreEqual(1.5, Double(PageView.Zoom), 0.0001, 'Zoom');
  Assert.AreEqual(90, PageView.ViewRotation, 'ViewRotation');
  Assert.IsTrue(PageView.ScrollMode = TPdfScrollMode.SinglePage, 'ScrollMode');
  Assert.IsFalse(PageView.HoverEnabled, 'HoverEnabled');
  Assert.IsFalse(PageView.SelectionEnabled, 'SelectionEnabled');
  Assert.IsFalse(PageView.FollowInternalLinks, 'FollowInternalLinks');
  Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(PageView.HoverColor), 'HoverColor');
  Assert.AreEqual(Cardinal(TAlphaColors.Lime), Cardinal(PageView.SelectionColor), 'SelectionColor');
  Assert.AreEqual(Cardinal(TAlphaColors.Blue), Cardinal(PageView.SearchHitColor), 'SearchHitColor');
  Assert.AreEqual(Cardinal(TAlphaColors.Yellow), Cardinal(PageView.CurrentSearchHitColor), 'CurrentSearchHitColor');
  Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(PageView.BackgroundColor), 'page view BackgroundColor');
  Assert.IsTrue(PageView.Align = TAlignLayout.Left, 'page view Align');
  Assert.IsTrue(PageView.Anchors = [TAnchorKind.akLeft, TAnchorKind.akBottom], 'page view Anchors');
  Assert.IsFalse(PageView.TabStop, 'page view TabStop');
  Assert.IsFalse(PageView.Visible, 'page view Visible');

  const Thumbnails = Target.FindComponent('Pdf4DThumbnails') as TPdf4DThumbnails;
  Assert.IsNotNull(Thumbnails, 'the thumbnails are read');
  Assert.AreSame(Document, Thumbnails.Document, 'the thumbnails link');
  Assert.AreEqual(77, Thumbnails.ThumbnailWidth, 'ThumbnailWidth');
  Assert.AreEqual(Cardinal(TAlphaColors.Red), Cardinal(Thumbnails.SelectedColor), 'SelectedColor');
  Assert.AreEqual(Cardinal(TAlphaColors.White), Cardinal(Thumbnails.BackgroundColor), 'thumbnails BackgroundColor');
  Assert.IsTrue(Thumbnails.Align = TAlignLayout.Right, 'thumbnails Align');
  Assert.IsFalse(Thumbnails.Visible, 'thumbnails Visible');

  const OutlineView = Target.FindComponent('Pdf4DOutlineView') as TPdf4DOutlineView;
  Assert.IsNotNull(OutlineView, 'the outline view is read');
  Assert.AreSame(Document, OutlineView.Document, 'the outline view link');
  Assert.IsTrue(OutlineView.Align = TAlignLayout.Top, 'outline view Align');
  Assert.IsFalse(OutlineView.Visible, 'outline view Visible');

  const SearchBar = Target.FindComponent('Pdf4DSearchBar') as TPdf4DSearchBar;
  Assert.IsNotNull(SearchBar, 'the search bar is read');
  Assert.AreSame(Document, SearchBar.Document, 'the search bar link');
  Assert.IsTrue(SearchBar.Align = TAlignLayout.Bottom, 'search bar Align');
  Assert.IsFalse(SearchBar.Visible, 'search bar Visible');

  const PrintDialog = Target.FindComponent('Pdf4DPrintDialog') as TPdf4DPrintDialog;
  Assert.IsNotNull(PrintDialog, 'the print dialog is read');
  Assert.AreSame(Document, PrintDialog.Document, 'the print dialog link');
  Assert.IsTrue(PrintDialog.RangeKind = TPdfPrintRangeKind.Pages, 'RangeKind');
  Assert.IsTrue(PrintDialog.Scale = TPdfPrintScale.ActualSize, 'Scale');
  Assert.AreEqual(3, PrintDialog.Copies, 'Copies');
  Assert.AreEqual(150, PrintDialog.MaxDpi, 'MaxDpi');
  Assert.IsFalse(PrintDialog.ShowProgress, 'ShowProgress');

  const Toolbar = Target.FindComponent('Pdf4DToolbar') as TPdf4DToolbar;
  Assert.IsNotNull(Toolbar, 'the toolbar is read');
  Assert.AreSame(Document, Toolbar.Document, 'the toolbar document link');
  Assert.AreSame(PageView, Toolbar.PageView, 'the toolbar page view link');
  Assert.AreSame(SearchBar, Toolbar.SearchBar, 'the toolbar search bar link');
  Assert.AreSame(PrintDialog, Toolbar.PrintDialog, 'the toolbar print dialog link');
  Assert.IsTrue(Toolbar.Buttons = [TPdf4DToolbarButton.Zoom, TPdf4DToolbarButton.Print], 'Buttons');

  const Viewer = Target.FindComponent('Pdf4DViewer') as TPdf4DViewer;
  Assert.IsNotNull(Viewer, 'the viewer is read');
  Assert.AreSame(Document, Viewer.Document, 'the viewer link');
  Assert.IsTrue(Viewer.Options = [TPdf4DViewerOption.Toolbar, TPdf4DViewerOption.Outline], 'Options');
  Assert.AreEqual(222, Viewer.SidePanelWidth, 'SidePanelWidth');
  Assert.IsFalse(Viewer.AskPassword, 'AskPassword');
  Assert.IsFalse(Viewer.Visible, 'viewer Visible');

  var Index := 0;
  for var ActionClass in ActionClasses do
  begin
    const ActionName = Copy(ActionClass.ClassName, 2, MaxInt);
    const Source = FForm.FindComponent(ActionName);
    const Read = Target.FindComponent(ActionName);
    Assert.IsNotNull(Read, ActionName + ' is read');
    Assert.IsTrue(Read is ActionClass, ActionName + ' has its class');
    CheckAction(Source, Read, Index);
    if Read is TPdf4DPageViewAction then
    begin
      Assert.AreSame(PageView, TPdf4DPageViewAction(Read).PageView, ActionName + ' page view link');
    end
    else if Read is TPdf4DDocumentAction then
    begin
      Assert.AreSame(Document, TPdf4DDocumentAction(Read).Document, ActionName + ' document link');
    end;
    if Read is TPdf4DPrintAction then
    begin
      Assert.AreSame(PrintDialog, TPdf4DPrintAction(Read).PrintDialog, ActionName + ' print dialog link');
    end;
    if Read is TPdf4DSearchAction then
    begin
      Assert.AreSame(SearchBar, TPdf4DSearchAction(Read).SearchBar, ActionName + ' search bar link');
    end;
    Inc(Index);
  end;
end;

procedure TPdf4DFmxStreamingTests.TestAllComponentsStreamRoundTrip;
begin
  for var ComponentClass in ComponentClasses + ActionClasses do
  begin
    MakeComponent(ComponentClass);
  end;
  ChangeAllComponents;

  const Target = RoundTrip;
  try
    CheckAllComponents(Target);
  finally
    Target.Free;
  end;
end;

procedure TPdf4DFmxStreamingTests.TestDefaultsAreNotStreamed;
begin
  // What every control or action writes whatever its value: the position and size of a control (FMX streams them as sub-properties), the
  // text of an action (as the standard actions do) and the viewport of a tree view (-1 until it is laid out, as for a standard TTreeView)
  const Allowed: TArray<string> = [
    'Viewport.Width', 'Viewport.Height', 'Position.X', 'Position.Y', 'Size.Width', 'Size.Height', 'Size.PlatformDefault', 'TabOrder', 'Text', 'Hint', 'ImageIndex', 'ShortCut'];

  const Unexpected = TStringList.Create;
  try
    for var ComponentClass in ComponentClasses + ActionClasses do
    begin
      const Component = MakeComponent(ComponentClass);
      const Properties = StreamedProperties(Component);
      try
        for var Line in Properties do
        begin
          const PropertyName = Copy(Line, 1, Pos(' = ', Line) - 1);
          if not MatchStr(PropertyName, Allowed) then
          begin
            Unexpected.Add(ComponentClass.ClassName + '.' + Line);
          end;
        end;
      finally
        Properties.Free;
      end;
    end;

    Assert.AreEqual('', Unexpected.CommaText, 'properties that are streamed with their default value');
  finally
    Unexpected.Free;
  end;
end;

procedure TPdf4DFmxStreamingTests.TestComponentsWorkInDesignState;
begin
  const FileName = TPath.Combine(TPath.GetTempPath, 'Pdf4DFmxStreamingTest.pdf');
  TFile.WriteAllBytes(FileName, TViewerDocuments.Invoice);
  try
    const Backend = TPdf4DSkiaBackend.Create(FForm);
    const Document = TDesignDocument.Create(FForm);
    Document.MakeDesigned;
    Document.Backend := Backend;
    Document.FileName := FileName;
    Assert.IsTrue(csDesigning in Document.ComponentState, 'the document is being designed');

    const Viewer = TPdf4DViewer.Create(FForm);
    TDesignAccess(Viewer).SetDesigning(True);
    Viewer.Parent := FForm;
    Viewer.Document := Document;

    const PageView = TPdf4DPageView.Create(FForm);
    TDesignAccess(PageView).SetDesigning(True);
    PageView.Parent := FForm;
    PageView.Document := Document;

    Document.Open;
    Assert.IsNull(Pointer(Document.Session), 'no session is made while designing');
    Assert.IsTrue(Document.State = TPdfDocumentState.Closed, 'the document stays closed');
  finally
    TFile.Delete(FileName);
  end;
end;

end.
