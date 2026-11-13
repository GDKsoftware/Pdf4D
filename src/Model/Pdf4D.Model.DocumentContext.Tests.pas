// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Model.DocumentContext.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support;

type
  [TestFixture]
  TDocumentContextTests = class
  private
    FDocuments: TModelTestDocuments;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestContextOwnsCachedObjects;

    [Test]
    procedure TestContextWithoutDocumentHasDefaults;

    [Test]
    procedure TestToUnicodeBudgetIsChargedAndExhausted;

    [Test]
    procedure TestAddingTheSameValueAgainKeepsIt;

    [Test]
    procedure TestPageCarriesContext;

    [Test]
    procedure TestDifferentValueForTheSameKeyRaises;

    [Test]
    procedure TestModelConstructorsRejectNilContext;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Common.SharedInstance.Tests,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.DocumentCatalog,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.PageTree;

{ TDocumentContextTests }

procedure TDocumentContextTests.Setup;
begin
  FDocuments := TModelTestDocuments.Create;
  TTrackedObject.ResetCounters;
end;

procedure TDocumentContextTests.TearDown;
begin
  FDocuments.Free;
end;

procedure TDocumentContextTests.TestContextOwnsCachedObjects;
begin
  const KeyOne = TObject.Create;
  const KeyTwo = TObject.Create;
  try
    const Context = TPDDocumentContext.Create(nil);
    try
      Context.AddCachedObject(KeyOne, TTrackedObject.Create);
      Context.AddCachedObject(KeyTwo, TTrackedObject.Create);

      var Found: TObject;
      Assert.IsTrue(Context.TryGetCachedObject(KeyTwo, Found));
      Assert.IsTrue(Found is TTrackedObject);
      Assert.IsFalse(Context.TryGetCachedObject(Context, Found));
      Assert.AreEqual(0, TTrackedObject.Freed);
    finally
      Context.Free;
    end;
    Assert.AreEqual(2, TTrackedObject.Freed);
  finally
    KeyTwo.Free;
    KeyOne.Free;
  end;
end;

procedure TDocumentContextTests.TestToUnicodeBudgetIsChargedAndExhausted;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxToUnicodeMappings := 10;
  const Context = TPDDocumentContext.Create(nil, Options);
  try
    Assert.IsTrue(Context.TryChargeToUnicodeMappings(6));
    Assert.IsTrue(Context.TryChargeToUnicodeMappings(4), 'the limit itself is allowed');
    Assert.IsFalse(Context.IsToUnicodeBudgetExhausted);

    Assert.IsFalse(Context.TryChargeToUnicodeMappings(1));
    Assert.IsTrue(Context.IsToUnicodeBudgetExhausted);
    Assert.IsFalse(Context.TryChargeToUnicodeMappings(0), 'nothing is accepted once the budget is gone');
  finally
    Context.Free;
  end;
end;

procedure TDocumentContextTests.TestContextWithoutDocumentHasDefaults;
begin
  const Context = TPDDocumentContext.Create(nil);
  try
    Assert.IsNull(Context.CosDocument);
    Assert.IsNull(Context.Log);
    Assert.AreEqual(DefaultMaxFormXObjectDepth, Context.Options.MaxFormXObjectDepth);
  finally
    Context.Free;
  end;
end;

procedure TDocumentContextTests.TestAddingTheSameValueAgainKeepsIt;
begin
  const Key = TObject.Create;
  try
    const Context = TPDDocumentContext.Create(nil);
    try
      const Value = TTrackedObject.Create;
      Context.AddCachedObject(Key, Value);
      Context.AddCachedObject(Key, Value);
      Assert.AreEqual(0, TTrackedObject.Freed);
    finally
      Context.Free;
    end;
    Assert.AreEqual(1, TTrackedObject.Freed);
  finally
    Key.Free;
  end;
end;

procedure TDocumentContextTests.TestPageCarriesContext;
begin
  const Builder = TModelTestDocuments.NewBuilderWithPages(2, '');
  try
    const Document = FDocuments.Open(Builder);

    Assert.IsNotNull(Document.Context);
    Assert.AreSame(Document.Context, Document.Pages.Get(0).Context);
    Assert.AreSame(Document.Context, Document.Pages.Get(1).Context);
    Assert.AreSame(Document.CosDocument, Document.Context.CosDocument);
    Assert.IsNotNull(Document.Context.Log);
  finally
    Builder.Free;
  end;
end;

procedure TDocumentContextTests.TestDifferentValueForTheSameKeyRaises;
begin
  const Key = TObject.Create;
  try
    const Context = TPDDocumentContext.Create(nil);
    try
      const First = TTrackedObject.Create;
      Context.AddCachedObject(Key, First);

      const Second = TTrackedObject.Create;
      try
        Assert.WillRaise(
          procedure
          begin
            Context.AddCachedObject(Key, Second);
          end,
          EArgumentException);
      finally
        Second.Free;
      end;

      var Found: TObject;
      Assert.IsTrue(Context.TryGetCachedObject(Key, Found));
      Assert.AreSame(First, Found, 'The earlier value is kept and not freed');
      Assert.AreEqual(1, TTrackedObject.Freed, 'Only Second was freed');
    finally
      Context.Free;
    end;
  finally
    Key.Free;
  end;
end;

procedure TDocumentContextTests.TestModelConstructorsRejectNilContext;
begin
  const Dictionary = TCosDictionary.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        TPDDocumentCatalog.Create(Dictionary, nil);
      end,
      EArgumentNilException);
    Assert.WillRaise(
      procedure
      begin
        TPDPageTree.Create(Dictionary, nil);
      end,
      EArgumentNilException);
    Assert.WillRaise(
      procedure
      begin
        TPDPage.Create(Dictionary, nil);
      end,
      EArgumentNilException);
  finally
    Dictionary.Free;
  end;
end;

end.
