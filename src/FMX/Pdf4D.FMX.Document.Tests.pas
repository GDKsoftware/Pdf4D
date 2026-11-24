// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.FMX.Document.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Tests.FmxHost;

type
  [TestFixture]
  TPdf4DFmxDocumentTests = class
  private
    FHost: TFmxTestHost;

  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDocumentSharesCoreBehaviour;
    [Test]
    procedure TestOpenWithoutBackendRaises;
    [Test]
    procedure TestPublishedPropertiesAreTheOnesOfTheVclDocument;
  end;

implementation

uses
  System.TypInfo,
  System.Classes,
  Pdf4D.Viewer.Types,
  Pdf4D.Viewer.ResourceStrings,
  Pdf4D.FMX.Document,
  Pdf4D.FMX.Backend.Skia,
  Pdf4D.Tests.ViewerDocuments;

const
  ClientWidth = 200;
  ClientHeight = 150;
  InvoicePages = 2;

{ TPdf4DFmxDocumentTests }

procedure TPdf4DFmxDocumentTests.Setup;
begin
  FHost := TFmxTestHost.Create(ClientWidth, ClientHeight);
  // The component takes the place of the backend that the host installs
  FHost.RemoveBackend;
end;

procedure TPdf4DFmxDocumentTests.TearDown;
begin
  FreeAndNil(FHost);
end;

procedure TPdf4DFmxDocumentTests.TestDocumentSharesCoreBehaviour;
begin
  const Backend = TPdf4DSkiaBackend.Create(FHost.Form);
  FHost.Document.Backend := Backend;

  Assert.IsTrue(FHost.Open(TViewerDocuments.Invoice), 'the document opens: ' + FHost.OpenErrorMessage);

  Assert.AreEqual(InvoicePages, FHost.Document.PageCount);
  Assert.AreEqual(Ord(TPdfDocumentState.Open), Ord(FHost.Document.State));
end;

procedure TPdf4DFmxDocumentTests.TestOpenWithoutBackendRaises;
begin
  Assert.WillRaiseWithMessage(
    procedure
    begin
      FHost.Open(TViewerDocuments.Invoice);
    end,
    EPdfViewerException,
    SNoRenderBackend);
end;

procedure TPdf4DFmxDocumentTests.TestPublishedPropertiesAreTheOnesOfTheVclDocument;
begin
  const Expected: TArray<string> = ['FileName', 'Password', 'Backend', 'IgnorePermissions', 'PageTextCacheCount', 'OnOpened', 'OnOpenError',
                                    'OnClosed', 'OnLog'];

  for var Name in Expected do
  begin
    Assert.IsNotNull(GetPropInfo(TPdf4DDocument, Name), Format('%s is published', [Name]));
  end;
end;

end.
