// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.FileNameEditor;

{$EXCESSPRECISION OFF}

interface

uses
  DesignIntf,
  DesignEditors;

type
  // The property editor of the FileName of a document: a button that opens the file dialog, for PDF files
  TPdf4DFileNameProperty = class(TStringProperty)
  public
    function GetAttributes: TPropertyAttributes; override;
    procedure Edit; override;
  end;

implementation

uses
  System.SysUtils,
  FMX.Dialogs;

const
  // The IDE is in English; the text of the dialog is not part of the runtime resource strings
  PdfFileFilter = 'PDF files (*.pdf)|*.pdf';

{ TPdf4DFileNameProperty }

function TPdf4DFileNameProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paRevertable];
end;

procedure TPdf4DFileNameProperty.Edit;
begin
  const Dialog = TOpenDialog.Create(nil);
  try
    Dialog.Filter := PdfFileFilter;
    Dialog.FileName := GetValue;
    if Dialog.Execute then
    begin
      SetValue(Dialog.FileName);
    end;
  finally
    Dialog.Free;
  end;
end;

end.
