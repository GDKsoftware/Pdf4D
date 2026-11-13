// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/documentnavigation/destination/PDDestination.java and
// PDPageDestination.java (3.0.8), the read side. The work is done by TPDDestinationResolver.
unit Pdf4D.Model.Destination;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base,
  Pdf4D.Model.Document;

type
  TPDDestination = class
  public
    // The index (from 0) in the page tree of the page that a destination points to. The destination is an explicit
    // destination (an array whose first item is a page dictionary, direct or by reference, or a page number that counts
    // from 0), a named destination (a name or a string, looked up in the name tree /Names /Dests and in /Dests of the
    // catalog) or a dictionary with /D that holds one of those. False when there is no page, the page is not in the
    // page tree or the value is malformed.
    //
    // The dictionary is a convenience of this function: PDFBox only accepts it as the value of a named destination, and
    // the outline items (TPDOutlineItem.TryGetPageIndex) follow PDFBox.
    class function TryResolvePageIndex(const Document: TPDDocument; const Destination: TCosBase; out PageIndex: Integer): Boolean; static;
  end;

implementation

uses
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Names;

{ TPDDestination }

class function TPDDestination.TryResolvePageIndex(const Document: TPDDocument; const Destination: TCosBase; out PageIndex: Integer): Boolean;
begin
  var Value := Destination;
  if Destination is TCosDictionary then
  begin
    if not TCosDictionary(Destination).TryGetDictionaryObject(TCosNames.D, Value) then
    begin
      PageIndex := -1;
      Exit(False);
    end;
  end;

  Result := Document.Catalog.DestinationResolver.TryResolvePageIndex(Value, PageIndex);
end;

end.
