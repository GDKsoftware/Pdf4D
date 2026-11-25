// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
program Pdf4DInvoiceDemo;

uses
  Vcl.Forms,
  Pdf4DInvoiceDemo.Main.Form in 'Pdf4DInvoiceDemo.Main.Form.pas' {FormMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
