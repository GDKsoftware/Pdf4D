// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Document;

{$EXCESSPRECISION OFF}

interface

uses
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.Document;

type
  // The document component for the form designer: the properties and events of the document without a framework
  TPdf4DDocument = class(TPdf4DCustomDocument)
  published
    property FileName;
    property Password;
    property Backend;
    property IgnorePermissions default False;
    property PageTextCacheCount default DefaultPageTextCacheCount;
    property OnOpened;
    property OnOpenError;
    property OnClosed;
    property OnLog;
  end;

implementation

end.
