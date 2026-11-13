// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Cos.Document.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.ObjectKey,
  Pdf4D.Cos.Resolver.Interfaces,
  Pdf4D.IO.RandomAccessRead;

type
  // Stands in for the parser: owned by the document, counts its own destruction
  TOwnedResolver = class(TCosObjectResolverBase)
  public
    class var DestroyedCount: Integer;

    destructor Destroy; override;

    function ResolveObject(const Key: TCosObjectKey): TCosBase; override;
  end;

  [TestFixture]
  TCosDocumentTests = class
  private
    function NewDocument(const Data: TBytes): TCosDocument;
    procedure AssertRawReadRaises(const Stream: TCosStream; const Expected: ExceptClass);

  public
    [Test]
    procedure TestPoolCreatesOneProxyPerKey;

    [Test]
    procedure TestForwardReferenceResolvesAfterResolverIsSet;

    [Test]
    procedure TestSelfReferencingObjectDoesNotHangOrLeak;

    [Test]
    procedure TestMutualReferencesDoNotHangOrLeak;

    [Test]
    procedure TestObjectLoadsLazilyAndCaches;

    [Test]
    procedure TestResolverOwnerIsFreedByTheDocument;

    [Test]
    procedure TestReplacingResolverFreesPreviousOwner;

    [Test]
    procedure TestObjectKeysAreSorted;

    [Test]
    procedure TestSetObjectReplacesLoadedContent;

    [Test]
    procedure TestStreamRawBytesFromSource;

    [Test]
    procedure TestStreamRawBytesApplyDecryptor;

    [Test]
    procedure TestStreamRawStreamOutlivesDocument;

    [Test]
    procedure TestStreamRawDataAndEmptyStream;

    [Test]
    procedure TestStreamSourceOutOfRangeRaises;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Null,
  Pdf4D.Cos.PdfObject,
  Pdf4D.Cos.Dictionary.Tests;

{ TOwnedResolver }

destructor TOwnedResolver.Destroy;
begin
  Inc(DestroyedCount);
  inherited;
end;

function TOwnedResolver.ResolveObject(const Key: TCosObjectKey): TCosBase;
begin
  Result := TCosInteger.Create(Key.Number * 10);
end;

{ TCosDocumentTests }

procedure TCosDocumentTests.AssertRawReadRaises(const Stream: TCosStream; const Expected: ExceptClass);
begin
  Assert.WillRaise(
    procedure
    begin
      Stream.CreateRawStream.Free;
    end,
    Expected,
    'stream read');
end;

function TCosDocumentTests.NewDocument(const Data: TBytes): TCosDocument;
begin
  Result := TCosDocument.Create(TRandomAccessRead.FromBytes(Data), TPdfLoadOptions.Default);
end;

procedure TCosDocumentTests.TestPoolCreatesOneProxyPerKey;
begin
  const Document = NewDocument(nil);
  try
    const First = Document.GetObjectFromPool(TCosObjectKey.Make(3, 0));
    const Again = Document.GetObjectFromPool(TCosObjectKey.Make(3, 0));
    const Other = Document.GetObjectFromPool(TCosObjectKey.Make(3, 1));

    Assert.AreSame(First, Again);
    Assert.AreNotSame(First, Other);
    Assert.IsFalse(First.IsLoaded);
    Assert.AreEqual('3 0 R', First.Key.ToString);
  finally
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestForwardReferenceResolvesAfterResolverIsSet;
begin
  const Resolver = TFakeResolver.Create;
  const Document = NewDocument(nil);
  try
    Resolver.Define(4,
      function: TCosBase
      begin
        Result := TCosInteger.Create(44);
      end);
    // The proxy exists before there is a resolver
    const Proxy = Document.GetObjectFromPool(TCosObjectKey.Make(4, 0));
    Document.SetResolver(Resolver, nil);

    Assert.AreEqual<Int64>(44, (Proxy.GetObject as TCosInteger).Value);
  finally
    Document.Free;
    Resolver.Free;
  end;
end;

procedure TCosDocumentTests.TestSelfReferencingObjectDoesNotHangOrLeak;
begin
  const Document = NewDocument(nil);
  try
    const Looping = Document.GetObjectFromPool(TCosObjectKey.Make(1, 0));
    const Resolver = TFakeResolver.Create;
    try
      Resolver.Define(1,
        function: TCosBase
        begin
          const Dictionary = TCosDictionary.Create;
          Dictionary.SetItem('Self', Document.GetObjectFromPool(TCosObjectKey.Make(1, 0)));
          Dictionary.SetItem('Type', TCosName.Create('Loop'));
          Result := Dictionary;
        end);
      Document.SetResolver(Resolver, nil);

      var Loaded: TCosDictionary;
      Assert.IsTrue(Looping.GetObject is TCosDictionary);
      Loaded := TCosDictionary(Looping.GetObject);
      var Target: TCosDictionary;
      Assert.IsTrue(Loaded.TryGetCosDictionary('Self', Target));
      Assert.AreSame(Loaded, Target);
      Assert.AreEqual('Loop', Target.GetNameAsString('Type', ''));
    finally
      Document.SetResolver(nil, nil);
      Resolver.Free;
    end;
  finally
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestMutualReferencesDoNotHangOrLeak;
begin
  var Document := NewDocument(nil);
  var Resolver := TFakeResolver.Create;
  try
    Resolver.Define(1,
      function: TCosBase
      begin
        const Dictionary = TCosDictionary.Create;
        Dictionary.SetItem('Other', Document.GetObjectFromPool(TCosObjectKey.Make(2, 0)));
        Result := Dictionary;
      end);
    Resolver.Define(2,
      function: TCosBase
      begin
        const Dictionary = TCosDictionary.Create;
        Dictionary.SetItem('Other', Document.GetObjectFromPool(TCosObjectKey.Make(1, 0)));
        Result := Dictionary;
      end);
    Document.SetResolver(Resolver, nil);

    var First: TCosDictionary;
    var Second: TCosDictionary;
    var Back: TCosDictionary;
    First := Document.GetObjectFromPool(TCosObjectKey.Make(1, 0)).GetObject as TCosDictionary;
    Assert.IsTrue(First.TryGetCosDictionary('Other', Second));
    Assert.IsTrue(Second.TryGetCosDictionary('Other', Back));
    Assert.AreSame(First, Back);
  finally
    Document.Free;
    Resolver.Free;
  end;
end;

procedure TCosDocumentTests.TestObjectLoadsLazilyAndCaches;
begin
  const Resolver = TFakeResolver.Create;
  const Document = NewDocument(nil);
  try
    Resolver.Define(6,
      function: TCosBase
      begin
        Result := TCosInteger.Create(6);
      end);
    Document.SetResolver(Resolver, nil);
    const Proxy = Document.GetObjectFromPool(TCosObjectKey.Make(6, 0));

    Assert.AreEqual(0, Resolver.ResolveCount);
    Assert.IsFalse(Proxy.IsLoaded);
    Assert.IsFalse(Proxy.IsObjectNull);
    Assert.IsTrue(Proxy.IsLoaded);
    Assert.AreSame(Proxy.GetObject, Proxy.GetObject);
    Assert.AreEqual(1, Resolver.ResolveCount);
  finally
    Document.Free;
    Resolver.Free;
  end;
end;

procedure TCosDocumentTests.TestResolverOwnerIsFreedByTheDocument;
begin
  TOwnedResolver.DestroyedCount := 0;
  const Document = NewDocument(nil);
  try
    const Resolver = TOwnedResolver.Create;
    Document.SetResolver(Resolver, Resolver);
    const Proxy = Document.GetObjectFromPool(TCosObjectKey.Make(9, 0));

    Assert.AreEqual<Int64>(90, (Proxy.GetObject as TCosInteger).Value);
  finally
    Document.Free;
  end;
  Assert.AreEqual(1, TOwnedResolver.DestroyedCount);
end;

procedure TCosDocumentTests.TestReplacingResolverFreesPreviousOwner;
begin
  TOwnedResolver.DestroyedCount := 0;
  const Document = NewDocument(nil);
  try
    const First = TOwnedResolver.Create;
    Document.SetResolver(First, First);
    const Second = TOwnedResolver.Create;
    Document.SetResolver(Second, Second);
    Assert.AreEqual(1, TOwnedResolver.DestroyedCount);

    // Setting the same owner again must not free it
    Document.SetResolver(Second, Second);
    Assert.AreEqual(1, TOwnedResolver.DestroyedCount);
  finally
    Document.Free;
  end;
  Assert.AreEqual(2, TOwnedResolver.DestroyedCount);
end;

procedure TCosDocumentTests.TestObjectKeysAreSorted;
begin
  const Document = NewDocument(nil);
  try
    Document.XrefTable.Add(TCosObjectKey.Make(10, 0), 100);
    Document.XrefTable.Add(TCosObjectKey.Make(2, 1), -5);
    Document.XrefTable.Add(TCosObjectKey.Make(2, 0), 0);

    const Keys = Document.ObjectKeys;

    Assert.AreEqual(3, Integer(Length(Keys)));
    Assert.AreEqual('2 0 R', Keys[0].ToString);
    Assert.AreEqual('2 1 R', Keys[1].ToString);
    Assert.AreEqual('10 0 R', Keys[2].ToString);
    Assert.AreEqual<Int64>(-5, Int64(Document.XrefTable[TCosObjectKey.Make(2, 1)]));
  finally
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestSetObjectReplacesLoadedContent;
begin
  const Document = NewDocument(nil);
  try
    const Proxy = Document.GetObjectFromPool(TCosObjectKey.Make(5, 0));
    Proxy.SetObject(TCosInteger.Create(1));
    Proxy.SetObject(TCosInteger.Create(2));

    Assert.AreEqual<Int64>(2, (Proxy.GetObject as TCosInteger).Value);

    Proxy.SetObject(nil);
    Assert.IsTrue(Proxy.IsObjectNull);
  finally
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestStreamRawBytesFromSource;
begin
  const Document = NewDocument(TEncoding.ASCII.GetBytes('0123456789'));
  const Stream = TCosStream.Create;
  try
    Stream.SetRawSource(Document.Source, 3, 4);

    const Raw = Stream.CreateRawStream;
    try
      Assert.AreEqual<Int64>(4, Raw.Size);
      Assert.AreEqual('3456', TEncoding.ASCII.GetString(TBytesStream(Raw).Bytes, 0, 4));
    finally
      Raw.Free;
    end;
  finally
    Stream.Free;
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestStreamRawBytesApplyDecryptor;
begin
  const Document = NewDocument(TEncoding.ASCII.GetBytes('abcdef'));
  const Stream = TCosStream.Create;
  try
    Stream.SetRawSource(Document.Source, 0, 3);
    Stream.Decryptor :=
      function(Data: TBytes): TBytes
      begin
        Result := Copy(Data);
        for var Index := 0 to High(Result) do
        begin
          Result[Index] := Result[Index] xor 1;
        end;
      end;

    const Raw = Stream.CreateRawStream;
    try
      Assert.AreEqual('`cb', TEncoding.ASCII.GetString(TBytesStream(Raw).Bytes, 0, Integer(Raw.Size)));
    finally
      Raw.Free;
    end;
  finally
    Stream.Free;
    Document.Free;
  end;
end;

procedure TCosDocumentTests.TestStreamRawStreamOutlivesDocument;
begin
  const Document = NewDocument(TEncoding.ASCII.GetBytes('abcdef'));
  const Stream = TCosStream.Create;
  var Raw: TStream;
  try
    Stream.SetRawSource(Document.Source, 1, 2);
    Raw := Stream.CreateRawStream;
  finally
    Stream.Free;
    Document.Free;
  end;

  try
    Assert.AreEqual<Int64>(2, Raw.Size);
    Assert.AreEqual('bc', TEncoding.ASCII.GetString(TBytesStream(Raw).Bytes, 0, 2));
  finally
    Raw.Free;
  end;
end;

procedure TCosDocumentTests.TestStreamRawDataAndEmptyStream;
begin
  const Stream = TCosStream.Create;
  try
    const Empty = Stream.CreateRawStream;
    try
      Assert.AreEqual<Int64>(0, Empty.Size);
    finally
      Empty.Free;
    end;

    Stream.SetRawData(TEncoding.ASCII.GetBytes('xyz'));
    const Raw = Stream.CreateRawStream;
    try
      Assert.AreEqual<Int64>(3, Raw.Size);
    finally
      Raw.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TCosDocumentTests.TestStreamSourceOutOfRangeRaises;
begin
  const Document = NewDocument(TEncoding.ASCII.GetBytes('abc'));
  const Stream = TCosStream.Create;
  try
    Stream.SetRawSource(Document.Source, 2, High(Int64));
    AssertRawReadRaises(Stream, EPdfLimitExceededException);

    Stream.SetRawSource(Document.Source, High(Int64), 5);
    AssertRawReadRaises(Stream, EPdfParseException);
  finally
    Stream.Free;
    Document.Free;
  end;
end;

end.
