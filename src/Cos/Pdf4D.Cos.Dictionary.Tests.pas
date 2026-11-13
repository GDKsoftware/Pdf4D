unit Pdf4D.Cos.Dictionary.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Resolver.Interfaces;

type
  // Gives a fixed object per object number, a TCosNull for any other number
  TFakeResolver = class(TCosObjectResolverBase)
  private
    FFactories: TDictionary<Int64, TFunc<TCosBase>>;
    FResolveCount: Integer;

  public
    constructor Create;
    destructor Destroy; override;

    function ResolveObject(const Key: TCosObjectKey): TCosBase; override;

    procedure Define(const Number: Int64; const Factory: TFunc<TCosBase>);

    property ResolveCount: Integer read FResolveCount;
  end;

  // Counts how many instances were freed
  TTrackedValue = class(TCosBase)
  public
    class var FreedCount: Integer;

    destructor Destroy; override;
  end;

  [TestFixture]
  TCosDictionaryTests = class
  public
    [Test]
    procedure TestDictionaryKeepsInsertionOrder;

    [Test]
    procedure TestTypedGettersUseDefaults;

    [Test]
    procedure TestTypedGettersReadMatchingTypes;

    [Test]
    procedure TestTryGetDereferencesIndirect;

    [Test]
    procedure TestNullIndirectCountsAsAbsent;

    [Test]
    procedure TestNullValueCountsAsAbsent;

    [Test]
    procedure TestSharedIndirectFreedOnce;

    [Test]
    procedure TestSetObjectDuringLoadKeepsFirstContentAndFreesTheOther;

    [Test]
    procedure TestReplacingItemFreesOldDirectValue;

    [Test]
    procedure TestRemovingItemFreesDirectValueAndKeepsOrder;

    [Test]
    procedure TestSettingNilRemovesTheKey;

    [Test]
    procedure TestSettingTheSameValueAgainKeepsIt;

    [Test]
    procedure TestTryGetContainers;

    [Test]
    procedure TestDestroyFreesNestedDirectValues;

    [Test]
    procedure TestArrayDereferencesAndConvertsToFloats;

    [Test]
    procedure TestArrayAddOfNilStoresNull;

    [Test]
    procedure TestArrayRemoveLastHandsOverOwnership;

    [Test]
    procedure TestObjectKeyEqualityAndText;

    [Test]
    procedure TestObjectKeyComparerHashesEqualKeysAlike;
  end;

implementation

uses
  Pdf4D.Cos.PdfArray,
  Pdf4D.Cos.Boolean,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Float,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.PdfString;

{ TFakeResolver }

constructor TFakeResolver.Create;
begin
  inherited Create;
  FFactories := TDictionary<Int64, TFunc<TCosBase>>.Create;
end;

destructor TFakeResolver.Destroy;
begin
  FFactories.Free;
  inherited;
end;

function TFakeResolver.ResolveObject(const Key: TCosObjectKey): TCosBase;
begin
  Inc(FResolveCount);
  var Factory: TFunc<TCosBase>;
  if FFactories.TryGetValue(Key.Number, Factory) then
  begin
    Result := Factory();
  end
  else
  begin
    Result := TCosNull.Create;
  end;
end;

procedure TFakeResolver.Define(const Number: Int64; const Factory: TFunc<TCosBase>);
begin
  FFactories.AddOrSetValue(Number, Factory);
end;

{ TTrackedValue }

destructor TTrackedValue.Destroy;
begin
  Inc(FreedCount);
  inherited;
end;

{ TCosDictionaryTests }

procedure TCosDictionaryTests.TestDictionaryKeepsInsertionOrder;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('Zeta', TCosInteger.Create(1));
    Dictionary.SetItem('Alpha', TCosInteger.Create(2));
    Dictionary.SetItem('Mid', TCosInteger.Create(3));
    // Replacing keeps the position
    Dictionary.SetItem('Zeta', TCosInteger.Create(4));

    Assert.AreEqual(3, Dictionary.Count);
    Assert.AreEqual('Zeta,Alpha,Mid', string.Join(',', Dictionary.Keys));
    Assert.AreEqual(4, Dictionary.GetInt('Zeta', 0));
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestTypedGettersUseDefaults;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('Name', TCosName.Create('Value'));
    Dictionary.SetItem('Int', TCosInteger.Create(5));

    // Missing key
    Assert.AreEqual(9, Dictionary.GetInt('Missing', 9));
    Assert.AreEqual<Int64>(9, Dictionary.GetLong('Missing', 9));
    Assert.AreEqual<Single>(9.5, Dictionary.GetFloat('Missing', 9.5));
    Assert.IsTrue(Dictionary.GetBoolean('Missing', True));
    Assert.AreEqual('d', Dictionary.GetNameAsString('Missing', 'd'));
    Assert.AreEqual('d', Dictionary.GetString('Missing', 'd'));

    // Wrong type
    Assert.AreEqual(9, Dictionary.GetInt('Name', 9));
    Assert.AreEqual<Int64>(9, Dictionary.GetLong('Name', 9));
    Assert.AreEqual<Single>(9.5, Dictionary.GetFloat('Name', 9.5));
    Assert.IsTrue(Dictionary.GetBoolean('Int', True));
    Assert.AreEqual('d', Dictionary.GetNameAsString('Int', 'd'));
    Assert.AreEqual('d', Dictionary.GetString('Name', 'd'));
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestTypedGettersReadMatchingTypes;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('Int', TCosInteger.Create(5000000000));
    Dictionary.SetItem('Float', TCosFloat.Create(2.5));
    Dictionary.SetItem('Flag', TCosBoolean.Create(False));
    Dictionary.SetItem('Name', TCosName.Create('Value'));
    Dictionary.SetItem('Text', TCosString.Create(TEncoding.ASCII.GetBytes('abc'), False));

    Assert.AreEqual<Int64>(5000000000, Dictionary.GetLong('Int', 0));
    Assert.AreEqual<Single>(2.5, Dictionary.GetFloat('Float', 0));
    Assert.AreEqual(2, Dictionary.GetInt('Float', 0));
    Assert.IsFalse(Dictionary.GetBoolean('Flag', True));
    Assert.AreEqual('Value', Dictionary.GetNameAsString('Name', ''));
    Assert.AreEqual('abc', Dictionary.GetString('Text', ''));
    Assert.AreEqual('abc', Dictionary.GetNameAsString('Text', ''));
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestTryGetDereferencesIndirect;
begin
  const Resolver = TFakeResolver.Create;
  const Reference = TCosObject.Create(TCosObjectKey.Make(5, 0), Resolver);
  const Dictionary = TCosDictionary.Create;
  try
    Resolver.Define(5,
      function: TCosBase
      begin
        Result := TCosInteger.Create(7);
      end);
    Dictionary.SetItem('A', Reference);

    Assert.AreEqual(7, Dictionary.GetInt('A', 0));
    Assert.AreEqual(7, Dictionary.GetInt('A', 0));
    Assert.AreEqual(1, Resolver.ResolveCount, 'resolved once, then cached');
    Assert.IsTrue(Reference.IsLoaded);
    Assert.AreSame(Reference, Dictionary.GetItem('A'), 'raw access does not dereference');
  finally
    Dictionary.Free;
    Reference.Free;
    Resolver.Free;
  end;
end;

procedure TCosDictionaryTests.TestNullIndirectCountsAsAbsent;
begin
  const Resolver = TFakeResolver.Create;
  const Reference = TCosObject.Create(TCosObjectKey.Make(8, 0), Resolver);
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('Gone', Reference);

    var Value: TCosBase;
    Assert.IsFalse(Dictionary.TryGetDictionaryObject('Gone', Value));
    Assert.IsNull(Value);
    Assert.IsTrue(Dictionary.ContainsKey('Gone'));
    Assert.IsTrue(Reference.IsObjectNull);
    Assert.AreEqual(3, Dictionary.GetInt('Gone', 3));
  finally
    Dictionary.Free;
    Reference.Free;
    Resolver.Free;
  end;
end;

procedure TCosDictionaryTests.TestNullValueCountsAsAbsent;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('N', TCosNull.Create);

    var Value: TCosBase;
    Assert.IsFalse(Dictionary.TryGetDictionaryObject('N', Value));
    Assert.IsNotNull(Dictionary.GetItem('N'));
    Assert.IsNull(Dictionary.GetItem('Missing'));
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestSharedIndirectFreedOnce;
begin
  TTrackedValue.FreedCount := 0;
  const Resolver = TFakeResolver.Create;
  try
    Resolver.Define(1,
      function: TCosBase
      begin
        Result := TTrackedValue.Create;
      end);

    const Document = TCosDictionary.Create;
    const First = TCosDictionary.Create;
    const Second = TCosDictionary.Create;
    const Shared = TCosObject.Create(TCosObjectKey.Make(1, 0), Resolver);
    try
      First.SetItem('Shared', Shared);
      Second.SetItem('Shared', Shared);
      Document.SetItem('Unused', TCosInteger.Create(0));

      Assert.AreSame(First.GetItem('Shared'), Second.GetItem('Shared'));
      Shared.GetObject;
      First.Free;
      Assert.AreEqual(0, TTrackedValue.FreedCount, 'a dictionary does not free a reference');
      Second.Free;
      Assert.AreEqual(0, TTrackedValue.FreedCount);
    finally
      Document.Free;
      Shared.Free;
    end;
    Assert.AreEqual(1, TTrackedValue.FreedCount, 'the reference frees its content once');
  finally
    Resolver.Free;
  end;
end;

procedure TCosDictionaryTests.TestSetObjectDuringLoadKeepsFirstContentAndFreesTheOther;
begin
  TTrackedValue.FreedCount := 0;
  const Resolver = TFakeResolver.Create;
  try
    var Proxy: TCosObject := nil;
    var HandedOver: TCosBase := nil;
    Resolver.Define(1,
      function: TCosBase
      begin
        HandedOver := TTrackedValue.Create;
        Proxy.SetObject(HandedOver);
        Result := TTrackedValue.Create;
      end);

    Proxy := TCosObject.Create(TCosObjectKey.Make(1, 0), Resolver);
    try
      const Loaded = Proxy.GetObject;

      Assert.AreSame(HandedOver, Loaded, 'the content set while loading stays');
      Assert.AreEqual(1, TTrackedValue.FreedCount, 'the returned duplicate is freed, not leaked');
    finally
      Proxy.Free;
    end;
    Assert.AreEqual(2, TTrackedValue.FreedCount);
  finally
    Resolver.Free;
  end;
end;

procedure TCosDictionaryTests.TestReplacingItemFreesOldDirectValue;
begin
  TTrackedValue.FreedCount := 0;
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('A', TTrackedValue.Create);
    Dictionary.SetItem('A', TCosInteger.Create(1));

    Assert.AreEqual(1, TTrackedValue.FreedCount);
    Assert.AreEqual(1, Dictionary.Count);
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestRemovingItemFreesDirectValueAndKeepsOrder;
begin
  TTrackedValue.FreedCount := 0;
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('A', TCosInteger.Create(1));
    Dictionary.SetItem('B', TTrackedValue.Create);
    Dictionary.SetItem('C', TCosInteger.Create(3));

    Dictionary.RemoveItem('B');
    Dictionary.RemoveItem('Nothing');

    Assert.AreEqual(1, TTrackedValue.FreedCount);
    Assert.AreEqual('A,C', string.Join(',', Dictionary.Keys));
    Assert.AreEqual(3, Dictionary.GetInt('C', 0), 'the index is rebuilt');
    Assert.IsFalse(Dictionary.ContainsKey('B'));
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestSettingNilRemovesTheKey;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('A', TCosInteger.Create(1));
    Dictionary.SetItem('A', nil);

    Assert.AreEqual(0, Dictionary.Count);
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestSettingTheSameValueAgainKeepsIt;
begin
  TTrackedValue.FreedCount := 0;
  const Dictionary = TCosDictionary.Create;
  try
    const Value = TTrackedValue.Create;
    Dictionary.SetItem('A', Value);
    Dictionary.SetItem('A', Value);

    Assert.AreEqual(0, TTrackedValue.FreedCount);
  finally
    Dictionary.Free;
  end;
  Assert.AreEqual(1, TTrackedValue.FreedCount);
end;

procedure TCosDictionaryTests.TestTryGetContainers;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Dictionary.SetItem('Array', TCosArray.Create);
    Dictionary.SetItem('Dict', TCosDictionary.Create);
    Dictionary.SetItem('Stream', TCosStream.Create);

    var Items: TCosArray;
    var Child: TCosDictionary;
    var Stream: TCosStream;
    Assert.IsTrue(Dictionary.TryGetCosArray('Array', Items));
    Assert.IsFalse(Dictionary.TryGetCosArray('Dict', Items));
    Assert.IsNull(Items);
    Assert.IsTrue(Dictionary.TryGetCosDictionary('Dict', Child));
    Assert.IsTrue(Dictionary.TryGetCosDictionary('Stream', Child), 'a stream is a dictionary');
    Assert.IsFalse(Dictionary.TryGetCosDictionary('Array', Child));
    Assert.IsTrue(Dictionary.TryGetCosStream('Stream', Stream));
    Assert.IsFalse(Dictionary.TryGetCosStream('Dict', Stream));
    Assert.IsNull(Stream);
  finally
    Dictionary.Free;
  end;
end;

procedure TCosDictionaryTests.TestDestroyFreesNestedDirectValues;
begin
  TTrackedValue.FreedCount := 0;
  const Outer = TCosDictionary.Create;
  const Items = TCosArray.Create;
  Items.Add(TTrackedValue.Create);
  Items.Add(TTrackedValue.Create);
  const Inner = TCosDictionary.Create;
  Inner.SetItem('X', TTrackedValue.Create);
  Items.Add(Inner);
  Outer.SetItem('List', Items);

  Outer.Free;

  Assert.AreEqual(3, TTrackedValue.FreedCount);
end;

procedure TCosDictionaryTests.TestArrayDereferencesAndConvertsToFloats;
begin
  const Resolver = TFakeResolver.Create;
  const Reference = TCosObject.Create(TCosObjectKey.Make(2, 0), Resolver);
  const Items = TCosArray.Create;
  try
    Resolver.Define(2,
      function: TCosBase
      begin
        Result := TCosInteger.Create(10);
      end);
    Items.Add(TCosFloat.Create(1.5));
    Items.Add(Reference);
    Items.Add(TCosName.Create('NotANumber'));

    Assert.AreEqual(3, Items.Count);
    Assert.AreSame(Reference, Items.Get(1));
    Assert.IsTrue(Items.GetObject(1) is TCosInteger);
    Assert.AreEqual<Single>(1.5, Items.ToFloatArray[0]);
    Assert.AreEqual<Single>(10, Items.ToFloatArray[1]);
    Assert.AreEqual<Single>(0, Items.ToFloatArray[2]);

    var Count := 0;
    for var Item in Items do
    begin
      Assert.IsNotNull(Item);
      Inc(Count);
    end;
    Assert.AreEqual(3, Count);
  finally
    Items.Free;
    Reference.Free;
    Resolver.Free;
  end;
end;

procedure TCosDictionaryTests.TestArrayAddOfNilStoresNull;
begin
  const Items = TCosArray.Create;
  try
    Items.Add(nil);

    Assert.IsTrue(Items.Get(0) is TCosNull);
  finally
    Items.Free;
  end;
end;

procedure TCosDictionaryTests.TestArrayRemoveLastHandsOverOwnership;
begin
  const Items = TCosArray.Create;
  try
    Items.Add(TCosInteger.Create(1));
    Items.Add(TCosInteger.Create(2));

    const Removed = Items.RemoveLast;
    try
      Assert.AreEqual(Int64(2), TCosInteger(Removed).Value);
    finally
      Removed.Free;
    end;
    Assert.AreEqual(1, Items.Count);

    Items.RemoveLast.Free;
    Assert.WillRaise(
      procedure
      begin
        Items.RemoveLast;
      end,
      EArgumentOutOfRangeException);
  finally
    Items.Free;
  end;
end;

procedure TCosDictionaryTests.TestObjectKeyEqualityAndText;
begin
  const Key = TCosObjectKey.Make(12, 0);

  Assert.IsTrue(Key = TCosObjectKey.Make(12, 0));
  Assert.IsTrue(Key <> TCosObjectKey.Make(12, 1));
  Assert.IsTrue(Key <> TCosObjectKey.Make(13, 0));
  Assert.AreEqual('12 0 R', Key.ToString);
end;

procedure TCosDictionaryTests.TestObjectKeyComparerHashesEqualKeysAlike;
begin
  const Comparer = TCosObjectKeyComparer.Create;
  try
    const Left = TCosObjectKey.Make(4000000000, 2);
    const Right = TCosObjectKey.Make(4000000000, 2);

    Assert.IsTrue(Comparer.Equals(Left, Right));
    Assert.AreEqual(Comparer.GetHashCode(Left), Comparer.GetHashCode(Right));
    Assert.IsTrue(Comparer.Compare(TCosObjectKey.Make(1, 5), TCosObjectKey.Make(2, 0)) < 0);
    Assert.IsTrue(Comparer.Compare(TCosObjectKey.Make(2, 1), TCosObjectKey.Make(2, 0)) > 0);
    Assert.AreEqual(0, Comparer.Compare(Left, Right));
  finally
    Comparer.Free;
  end;
end;

end.
