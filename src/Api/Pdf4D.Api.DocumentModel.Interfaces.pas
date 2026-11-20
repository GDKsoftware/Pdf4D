// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Api.DocumentModel.Interfaces;

interface

uses
  Pdf4D.Model.Document;

type
  // Gives code that needs more than IPdfDocument (the renderer) the document of the model layer. A document implements it
  // next to IPdfDocument; ask for it with Supports.
  IPdfDocumentModel = interface
    ['{9F1B3D6A-7C28-4E05-A3B9-5D0E8F2C4A71}']
    // Valid as long as the IPdfDocument, or a page of it, is alive
    function ModelDocument: TPDDocument;
  end;

implementation

end.
