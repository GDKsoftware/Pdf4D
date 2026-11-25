// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
program Pdf4DInvoiceDemoFmx;

uses
  System.StartUpCopy,
  FMX.Forms,
  Pdf4DInvoiceDemoFmx.Main.Form in 'Pdf4DInvoiceDemoFmx.Main.Form.pas' {FormMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
