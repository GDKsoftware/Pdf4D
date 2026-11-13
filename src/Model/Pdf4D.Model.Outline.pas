// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/interactive/documentnavigation/outline/PDDocumentOutline.java (3.0.8),
// the read side
unit Pdf4D.Model.Outline;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DestinationResolver,
  Pdf4D.Model.OutlineItem;

type
  // The root of the outline (the bookmarks), which owns all items that it gives out. Unlike PDFBox it does not set
  // /Type /Outlines in the dictionary: nothing in a loaded document is changed.
  TPDDocumentOutline = class(TPDOutlineNode)
  private
    FOwnedItems: TPDOutlineItems;

  public
    // The dictionary and the resolver are not owned
    constructor Create(const Dictionary: TCosDictionary; const Resolver: TPDDestinationResolver);
    destructor Destroy; override;

    // The root of the outline is always open
    function IsNodeOpen: Boolean; override;
  end;

implementation

{ TPDDocumentOutline }

constructor TPDDocumentOutline.Create(const Dictionary: TCosDictionary; const Resolver: TPDDestinationResolver);
begin
  const Items = TPDOutlineItems.Create(Resolver);
  try
    inherited Create(Dictionary, Items);
  except
    Items.Free;
    raise;
  end;
  FOwnedItems := Items;
end;

destructor TPDDocumentOutline.Destroy;
begin
  FOwnedItems.Free;
  inherited;
end;

function TPDDocumentOutline.IsNodeOpen: Boolean;
begin
  Result := True;
end;

end.
