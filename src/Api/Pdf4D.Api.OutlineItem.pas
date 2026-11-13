unit Pdf4D.Api.OutlineItem;

interface

uses
  Pdf4D.Api.DocumentHandle,
  Pdf4D.Api.Outline.Interfaces,
  Pdf4D.Model.OutlineItem;

type
  TPdfOutlineItem = class(TInterfacedObject, IPdfOutlineItem)
  private
    FHandle: IPdfDocumentHandle;
    FItem: TPDOutlineItem;

  public
    constructor Create(const Handle: IPdfDocumentHandle; const Item: TPDOutlineItem);

    // The items of a list of the model as API objects
    class function Wrap(const Handle: IPdfDocumentHandle; const Items: TArray<TPDOutlineItem>): TArray<IPdfOutlineItem>; static;

    function Title: string;
    function TryGetPageIndex(out Index: Integer): Boolean;
    function Children: TArray<IPdfOutlineItem>;
  end;

implementation

{ TPdfOutlineItem }

constructor TPdfOutlineItem.Create(const Handle: IPdfDocumentHandle; const Item: TPDOutlineItem);
begin
  inherited Create;
  FHandle := Handle;
  FItem := Item;
end;

class function TPdfOutlineItem.Wrap(const Handle: IPdfDocumentHandle; const Items: TArray<TPDOutlineItem>): TArray<IPdfOutlineItem>;
begin
  SetLength(Result, Length(Items));
  for var Position := 0 to High(Items) do
  begin
    Result[Position] := TPdfOutlineItem.Create(Handle, Items[Position]);
  end;
end;

function TPdfOutlineItem.Title: string;
begin
  Result := FItem.Title;
end;

function TPdfOutlineItem.TryGetPageIndex(out Index: Integer): Boolean;
begin
  Result := FItem.TryGetPageIndex(Index);
end;

function TPdfOutlineItem.Children: TArray<IPdfOutlineItem>;
begin
  Result := Wrap(FHandle, FItem.Children);
end;

end.
