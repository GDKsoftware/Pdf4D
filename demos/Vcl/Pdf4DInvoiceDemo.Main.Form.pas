// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4DInvoiceDemo.Main.Form;

// The use case of the viewer: an invoice form next to the PDF of the invoice. A field that gets the focus is looked up in the text of the
// PDF and marked there; a click on a word of the PDF fills the field that has the focus. All of it goes through the public API; the
// demo has no logic of its own for the viewer.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Pdf4D.Api.Document.Interfaces,
  Pdf4D.Viewer.Types,
  Pdf4D.Vcl.Backend.Skia,
  Pdf4D.Vcl.Document,
  Pdf4D.Vcl.Viewer;

type
  TFormMain = class(TForm)
    PanelFields: TPanel;
    ButtonOpen: TButton;
    LabelInvoiceNumber: TLabel;
    EditInvoiceNumber: TEdit;
    LabelInvoiceDate: TLabel;
    EditInvoiceDate: TEdit;
    LabelAmount: TLabel;
    EditAmount: TEdit;
    Pdf4DViewer1: TPdf4DViewer;
    Pdf4DDocument1: TPdf4DDocument;
    Pdf4DSkiaBackend1: TPdf4DSkiaBackend;
    OpenDialog1: TOpenDialog;
    procedure FormShow(Sender: TObject);
    procedure ButtonOpenClick(Sender: TObject);
    procedure EditEnter(Sender: TObject);
    procedure Pdf4DDocument1Opened(Sender: TObject);
    procedure Pdf4DViewer1TextSelected(Sender: TObject; const Selection: TPdfTextSelection);
  private
    // The document of the application itself. The document of the viewer lives on its worker thread and is never used from the UI thread.
    FDocument: IPdfDocument;
    FActiveEdit: TEdit;
    FIsStartFileHandled: Boolean;

    procedure OpenStartFile;
    procedure ChooseAndOpenInvoice;
    procedure OpenInvoice(const FileName: string);
    procedure MarkValueOfActiveField;
    function TryMarkValue(const Value: string): Boolean;
    function TryMarkOnPage(const PageIndex: Integer; const Value: string): Boolean;
    procedure FillActiveField(const Text: string);
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  System.UITypes,
  Pdf4D.Common.Defines,
  Pdf4D.Api.Document,
  Pdf4D.Api.TextLayout.Interfaces;

const
  // The ellipse is filled, so the colour is translucent to leave the text under it readable
  MarkerColor: TAlphaColor = $66FF0000;

{ TFormMain }

procedure TFormMain.FormShow(Sender: TObject);
begin
  OpenStartFile;
end;

procedure TFormMain.ButtonOpenClick(Sender: TObject);
begin
  ChooseAndOpenInvoice;
end;

procedure TFormMain.EditEnter(Sender: TObject);
begin
  FActiveEdit := Sender as TEdit;
  MarkValueOfActiveField;
end;

procedure TFormMain.Pdf4DDocument1Opened(Sender: TObject);
begin
  MarkValueOfActiveField;
end;

procedure TFormMain.Pdf4DViewer1TextSelected(Sender: TObject; const Selection: TPdfTextSelection);
begin
  FillActiveField(Selection.Text);
end;

procedure TFormMain.OpenStartFile;
begin
  if FIsStartFileHandled then
  begin
    Exit;
  end;

  FIsStartFileHandled := True;

  const HasStartFile = (ParamCount > 0);
  if HasStartFile then
  begin
    OpenInvoice(ParamStr(1));
  end;
end;

procedure TFormMain.ChooseAndOpenInvoice;
begin
  if OpenDialog1.Execute then
  begin
    OpenInvoice(OpenDialog1.FileName);
  end;
end;

procedure TFormMain.OpenInvoice(const FileName: string);
begin
  try
    FDocument := TPdfDocument.Load(FileName);
  except
    on E: EPdfException do
    begin
      FDocument := nil;
      MessageDlg(E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;

  Pdf4DDocument1.FileName := FileName;
  Pdf4DDocument1.Open;
end;

procedure TFormMain.MarkValueOfActiveField;
begin
  const IsReady = (FDocument <> nil) and (FActiveEdit <> nil) and (Pdf4DDocument1.State = TPdfDocumentState.Open);
  if not IsReady then
  begin
    Exit;
  end;

  Pdf4DDocument1.Overlays.Clear;

  const FieldText: string = FActiveEdit.Text;
  const Value = FieldText.Trim;
  if not Value.IsEmpty then
  begin
    TryMarkValue(Value);
  end;
end;

function TFormMain.TryMarkValue(const Value: string): Boolean;
begin
  Result := False;

  for var PageIndex := 0 to FDocument.PageCount - 1 do
  begin
    if TryMarkOnPage(PageIndex, Value) then
    begin
      Exit(True);
    end;
  end;
end;

function TFormMain.TryMarkOnPage(const PageIndex: Integer; const Value: string): Boolean;
begin
  const PageText = FDocument.Page(PageIndex).ExtractTextWithPositions;
  const Start = Pos(Value, PageText.Text);

  Result := (Start > 0);
  if not Result then
  begin
    Exit;
  end;

  for var Fragment in PageText.Locate(Start, Value.Length) do
  begin
    Pdf4DDocument1.Overlays.Add(Fragment.PageIndex, Fragment.Quads, TPdfOverlayStyle.Ellipse, MarkerColor);
    Pdf4DViewer1.PageView.ScrollIntoView(Fragment.PageIndex, Fragment.Quads);
  end;
end;

procedure TFormMain.FillActiveField(const Text: string);
begin
  if FActiveEdit = nil then
  begin
    Exit;
  end;

  FActiveEdit.Text := Text.Replace(sLineBreak, ' ').Trim;
  MarkValueOfActiveField;
end;

end.
