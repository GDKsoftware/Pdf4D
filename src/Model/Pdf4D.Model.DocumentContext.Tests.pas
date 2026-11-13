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
    procedure TestAddingTheSameValueAgainKeepsIt;

    [Test]
    procedure TestPageCarriesContext;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Common.SharedInstance.Tests,
  Pdf4D.Model.DocumentContext;

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

end.
