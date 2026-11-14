// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/documentinterchange/markedcontent/PDMarkedContent.java (3.0.8), the part
// that text extraction reads
unit Pdf4D.Model.MarkedContent;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary;

type
  // The tag, the marked-content identifier and the actual text of a BMC or BDC sequence.
  //
  // The property list of a BDC is an operand of the content stream, which is gone when the operator has been processed. So the
  // values are copied in the constructor and the dictionary is not kept (PDMarkedContent.getProperties has no counterpart).
  TPDMarkedContent = class
  private
    FTag: string;
    FMcid: Integer;
    FHasActualText: Boolean;
    FActualText: string;

  public
    // Properties may be nil and is only read during this call
    constructor Create(const Tag: string; const Properties: TCosDictionary);

    // PDMarkedContent.getActualText: false when there are no properties or no /ActualText string
    function TryGetActualText(out Text: string): Boolean;

    property Tag: string read FTag;
    // -1 when there is none
    property Mcid: Integer read FMcid;
  end;

implementation

uses
  Pdf4D.Cos.Names;

{ TPDMarkedContent }

constructor TPDMarkedContent.Create(const Tag: string; const Properties: TCosDictionary);
begin
  inherited Create;
  FTag := Tag;
  FMcid := -1;
  if Assigned(Properties) then
  begin
    FMcid := Properties.GetInt(TCosNames.MCID, -1);
    FHasActualText := Properties.TryGetString(TCosNames.ActualText, FActualText);
  end;
end;

function TPDMarkedContent.TryGetActualText(out Text: string): Boolean;
begin
  Text := FActualText;
  Result := FHasActualText;
end;

end.
