// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Vcl.FileNameEditor;

{$EXCESSPRECISION OFF}

interface

uses
  Vcl.Dialogs,
  VCLEditors;

type
  // The property editor of the FileName of a document: a button that opens the file dialog, for PDF files
  TPdf4DFileNameProperty = class(TFileNameProperty)
  protected
    procedure GetDialogOptions(Dialog: TOpenDialog); override;
  end;

implementation

const
  // The IDE is in English; the text of the dialog is not part of the runtime resource strings
  PdfFileFilter = 'PDF files (*.pdf)|*.pdf';

{ TPdf4DFileNameProperty }

procedure TPdf4DFileNameProperty.GetDialogOptions(Dialog: TOpenDialog);
begin
  inherited;
  Dialog.Filter := PdfFileFilter;
end;

end.
