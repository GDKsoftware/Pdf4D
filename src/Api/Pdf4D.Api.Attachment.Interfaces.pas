// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Api.Attachment.Interfaces;

interface

uses
  System.SysUtils;

type
  // A file that is embedded in the document. The attachment keeps its document alive.
  IPdfAttachment = interface
    ['{5D07B3E9-A1C2-4786-B9F4-2E8C6A1D0F73}']

    function FileName: string;
    function Description: string;
    // The size that the document states. False when it states none.
    function TryGetSize(out Size: Int64): Boolean;
    // The decoded content. Raises an EPdfException descendant when the file has no stream or cannot be decoded.
    function Data: TBytes;
  end;

implementation

end.
