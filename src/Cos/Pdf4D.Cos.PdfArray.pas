// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSArray.java (3.0.8)
unit Pdf4D.Cos.PdfArray;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Cos.Base;

type
  // Owns its items, except TCosObject items: those belong to the document.
  TCosArray = class(TCosBase)
  private
    FItems: TList<TCosBase>;
    // Decided when an item is added: a destructor must not look at a TCosObject again, the document may have freed it
    FOwned: TList<Boolean>;

    function GetCount: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    // The array takes ownership, except of a TCosObject. A nil becomes a TCosNull.
    procedure Add(const Item: TCosBase);

    // The raw item, a TCosObject is not resolved
    function Get(const Index: Integer): TCosBase;

    // The item with an indirect reference resolved. Never nil: a missing target is a TCosNull.
    function GetObject(const Index: Integer): TCosBase;

    // Removes the last item and hands it to the caller, who owns it again, except of a TCosObject.
    function RemoveLast: TCosBase;

    // Port of COSArray.remove(COSBase): removes the first item that is this instance and frees it unless it is a
    // TCosObject. False when the array does not hold it.
    function Remove(const Item: TCosBase): Boolean;

    // Removes each item of Items once (the same item twice in Items removes two entries of the array), in a single pass.
    // Frees what it removes, like Remove.
    procedure RemoveItems(const Items: TList<TCosBase>);

    function GetEnumerator: TList<TCosBase>.TEnumerator;

    // Port of COSArray.toFloatArray: an item that is not a number gives 0
    function ToFloatArray: TArray<Single>;

    property Count: Integer read GetCount;
  end;

implementation

uses
  Pdf4D.Cos.Null,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfObject;

{ TCosArray }

constructor TCosArray.Create;
begin
  inherited Create;
  FItems := TList<TCosBase>.Create;
  FOwned := TList<Boolean>.Create;
end;

destructor TCosArray.Destroy;
begin
  for var Index := 0 to FItems.Count - 1 do
  begin
    if FOwned[Index] then
    begin
      FItems[Index].Free;
    end;
  end;
  FItems.Free;
  FOwned.Free;
  inherited;
end;

procedure TCosArray.Add(const Item: TCosBase);
begin
  if Assigned(Item) then
  begin
    FItems.Add(Item);
    FOwned.Add(not (Item is TCosObject));
  end
  else
  begin
    FItems.Add(TCosNull.Create);
    FOwned.Add(True);
  end;
end;

function TCosArray.Get(const Index: Integer): TCosBase;
begin
  Result := FItems[Index];
end;

function TCosArray.GetObject(const Index: Integer): TCosBase;
begin
  Result := FItems[Index];
  if Result is TCosObject then
  begin
    Result := TCosObject(Result).GetObject;
  end;
end;

function TCosArray.RemoveLast: TCosBase;
begin
  const LastIndex = FItems.Count - 1;
  const IsEmpty = (LastIndex < 0);
  if IsEmpty then
  begin
    raise EArgumentOutOfRangeException.Create('Cannot remove the last item of an empty array');
  end;

  Result := FItems[LastIndex];
  FItems.Delete(LastIndex);
  FOwned.Delete(LastIndex);
end;

function TCosArray.Remove(const Item: TCosBase): Boolean;
begin
  const Position = FItems.IndexOf(Item);
  Result := (Position >= 0);
  if Result then
  begin
    const IsOwned = FOwned[Position];
    FItems.Delete(Position);
    FOwned.Delete(Position);
    if IsOwned then
    begin
      Item.Free;
    end;
  end;
end;

procedure TCosArray.RemoveItems(const Items: TList<TCosBase>);
begin
  if Items.Count = 0 then
  begin
    Exit;
  end;

  const Pending = TDictionary<TCosBase, Integer>.Create;
  const Kept = TList<TCosBase>.Create;
  const KeptOwned = TList<Boolean>.Create;
  try
    for var Item in Items do
    begin
      var Count: Integer;
      Pending.TryGetValue(Item, Count);
      Pending.AddOrSetValue(Item, Count + 1);
    end;

    for var Position := 0 to FItems.Count - 1 do
    begin
      const Item = FItems[Position];
      var Count: Integer;
      if Pending.TryGetValue(Item, Count) and (Count > 0) then
      begin
        Pending[Item] := Count - 1;
        if FOwned[Position] then
        begin
          Item.Free;
        end;
      end
      else
      begin
        Kept.Add(Item);
        KeptOwned.Add(FOwned[Position]);
      end;
    end;

    FItems.Clear;
    FItems.AddRange(Kept);
    FOwned.Clear;
    FOwned.AddRange(KeptOwned);
  finally
    KeptOwned.Free;
    Kept.Free;
    Pending.Free;
  end;
end;

function TCosArray.GetEnumerator: TList<TCosBase>.TEnumerator;
begin
  Result := FItems.GetEnumerator;
end;

function TCosArray.ToFloatArray: TArray<Single>;
begin
  SetLength(Result, FItems.Count);
  for var Index := 0 to FItems.Count - 1 do
  begin
    const Item = GetObject(Index);
    if Item is TCosNumber then
    begin
      Result[Index] := TCosNumber(Item).FloatValue;
    end
    else
    begin
      Result[Index] := 0;
    end;
  end;
end;

function TCosArray.GetCount: Integer;
begin
  Result := FItems.Count;
end;

end.
