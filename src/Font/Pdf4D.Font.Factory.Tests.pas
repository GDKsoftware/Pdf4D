// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Font.Factory.Tests;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.Tests.Support;

type
  // A font that fails is parsed once, whatever the exception is
  [TestFixture]
  TFontFactoryTests = class
  private
    FModels: TModelTestDocuments;
    FCreateCount: Integer;

    procedure FailCreationWith(const FailureClass: ExceptClass);
    procedure CheckFailsOnceOnly(const FailureClass: ExceptClass);

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestNonPdfFailureIsRememberedAndRaisedAsParseException;

    [Test]
    procedure TestPdfFailureIsRemembered;

    [Test]
    procedure TestRangeErrorIsRememberedAndRaisedAsParseException;

    [Test]
    procedure TestMathErrorIsRememberedAndRaisedAsParseException;

    [Test]
    procedure TestLibraryFailureIsNotRemembered;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Font.Factory,
  Pdf4D.Model.Document,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Tests.TextDocuments;

const
  FontName = 'F1';

{ TFontFactoryTests }

procedure TFontFactoryTests.Setup;
begin
  FModels := TModelTestDocuments.Create;
  FCreateCount := 0;
end;

procedure TFontFactoryTests.TearDown;
begin
  TPDFontFactory.CreatorOverride := nil;
  FreeAndNil(FModels);
end;

procedure TFontFactoryTests.FailCreationWith(const FailureClass: ExceptClass);
begin
  TPDFontFactory.CreatorOverride :=
    function(const Dictionary: TCosDictionary; const Context: TPDDocumentContext): TPDFont
    begin
      Inc(FCreateCount);
      raise FailureClass.Create('Injected failure');
    end;
end;

procedure TFontFactoryTests.CheckFailsOnceOnly(const FailureClass: ExceptClass);
begin
  const Builder = TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, '');
  try
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, FontName);
    FailCreationWith(FailureClass);

    for var Attempt := 1 to 3 do
    begin
      Assert.WillRaise(
        procedure
        begin
          TPDFontFactory.GetFont(Dictionary, Document.Context);
        end,
        EPdfParseException);
    end;

    Assert.AreEqual(1, FCreateCount, 'the font is made once');
    Assert.IsTrue(TPDFontFactory.HasFailed(Dictionary, Document.Context));
  finally
    Builder.Free;
  end;
end;

procedure TFontFactoryTests.TestNonPdfFailureIsRememberedAndRaisedAsParseException;
begin
  CheckFailsOnceOnly(EConvertError);
end;

procedure TFontFactoryTests.TestPdfFailureIsRemembered;
begin
  CheckFailsOnceOnly(EPdfParseException);
end;

procedure TFontFactoryTests.TestRangeErrorIsRememberedAndRaisedAsParseException;
begin
  CheckFailsOnceOnly(ERangeError);
end;

procedure TFontFactoryTests.TestMathErrorIsRememberedAndRaisedAsParseException;
begin
  CheckFailsOnceOnly(EOverflow);
end;

procedure TFontFactoryTests.TestLibraryFailureIsNotRemembered;
begin
  const Builder = TTextTestDocuments.NewBuilder(TTextTestDocuments.HelveticaF1, '');
  try
    const Document = FModels.Open(Builder);
    const Dictionary = TTextTestDocuments.FontDictionary(Document, FontName);
    FailCreationWith(EAccessViolation);

    Assert.WillRaise(
      procedure
      begin
        TPDFontFactory.GetFont(Dictionary, Document.Context);
      end,
      EAccessViolation);

    Assert.IsFalse(TPDFontFactory.HasFailed(Dictionary, Document.Context));
  finally
    Builder.Free;
  end;
end;

end.
