unit Pdf4D.Api.Outline.Interfaces;

interface

type
  IPdfOutlineItem = interface;

  // An item of the outline (a bookmark). The item keeps its document alive.
  IPdfOutlineItem = interface
    ['{8E3A9F17-2C64-4B50-A1D8-7F0B5E92C3A4}']

    function Title: string;
    // The zero based index of the page that the item points to. False when there is no destination, no page, or the
    // destination is broken.
    function TryGetPageIndex(out Index: Integer): Boolean;
    function Children: TArray<IPdfOutlineItem>;
  end;

implementation

end.
