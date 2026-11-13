// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Cos.Stream.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary;

type
  [TestFixture]
  TCosStreamTests = class
  private
    function NewStream(const Raw: TBytes; const Filters: TArray<string>): TCosStream;
    function Decoded(const Stream: TCosStream): TBytes;
    function ToHexText(const Text: string): TBytes;

  public
    [Test]
    procedure TestStreamFilterChain;

    [Test]
    procedure TestStreamWithoutFilterGivesRawBytes;

    [Test]
    procedure TestGetFilterNames;

    [Test]
    procedure TestGetFilterNamesRejectsOtherTypes;

    [Test]
    procedure TestDecodeUntilImageFilter;

    [Test]
    procedure TestDecodeUntilImageFilterWithoutImageFilter;

    [Test]
    procedure TestDecodeUntilImageFilterAsFirstFilter;

    [Test]
    procedure TestCreateDecodedStreamRaisesOnImageFilter;

    [Test]
    procedure TestCreateDecodedStreamRaisesOnUnknownFilter;

    [Test]
    procedure TestDuplicateFiltersAreAppliedOnce;

    [Test]
    procedure TestLimitComesFromTheDocument;

    [Test]
    procedure TestDefaultLimitWithoutDocument;

    [Test]
    procedure TestDocumentLogReceivesFilterProblems;

    [Test]
    procedure TestDocumentMustBeACosDocument;

    [Test]
    procedure TestCryptFilterWithIdentityInAChain;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Document,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Filter.Tests.Support,
  Pdf4D.IO.RandomAccessRead;

{ TCosStreamTests }

function TCosStreamTests.NewStream(const Raw: TBytes; const Filters: TArray<string>): TCosStream;
begin
  Result := TCosStream.Create;
  Result.SetRawData(Raw);
  if Length(Filters) = 1 then
  begin
    Result.SetItem('Filter', TCosName.Create(Filters[0]));
  end
  else if Length(Filters) > 1 then
  begin
    const FilterArray = TCosArray.Create;
    for var Name in Filters do
    begin
      FilterArray.Add(TCosName.Create(Name));
    end;
    Result.SetItem('Filter', FilterArray);
  end;
end;

function TCosStreamTests.Decoded(const Stream: TCosStream): TBytes;
begin
  const Data = Stream.CreateDecodedStream;
  try
    SetLength(Result, Data.Size);
    Data.Position := 0;
    if Data.Size > 0 then
    begin
      Data.ReadBuffer(Result[0], Data.Size);
    end;
  finally
    Data.Free;
  end;
end;

function TCosStreamTests.ToHexText(const Text: string): TBytes;
begin
  Result := TFilterTestSupport.AsciiBytes(Text);
end;

procedure TCosStreamTests.TestStreamFilterChain;
begin
  const Original = TFilterTestSupport.AsciiBytes('Hello World, Hello World');
  var HexText := '';
  for var Value in TFilterTestSupport.Compress(Original) do
  begin
    HexText := HexText + IntToHex(Value, 2);
  end;

  const Stream = NewStream(ToHexText(HexText + '>'), ['AHx', 'Fl']);
  try
    Assert.AreEqual('Hello World, Hello World', TFilterTestSupport.AsciiString(Decoded(Stream)));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestStreamWithoutFilterGivesRawBytes;
begin
  const Stream = NewStream(ToHexText('plain'), []);
  try
    Assert.AreEqual('plain', TFilterTestSupport.AsciiString(Decoded(Stream)));
    Assert.AreEqual<Integer>(0, Length(Stream.DecodeUntilImageFilter.RemainingFilters));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestGetFilterNames;
begin
  const None = NewStream(nil, []);
  const Single = NewStream(nil, ['FlateDecode']);
  const Several = NewStream(nil, ['AHx', 'Fl', 'DCTDecode']);
  try
    Assert.AreEqual<Integer>(0, Length(None.GetFilterNames));
    Assert.AreEqual('FlateDecode', string.Join(',', Single.GetFilterNames));
    Assert.AreEqual('AHx,Fl,DCTDecode', string.Join(',', Several.GetFilterNames));
  finally
    Several.Free;
    Single.Free;
    None.Free;
  end;
end;

procedure TCosStreamTests.TestGetFilterNamesRejectsOtherTypes;
begin
  const Stream = NewStream(nil, []);
  try
    const FilterArray = TCosArray.Create;
    FilterArray.Add(TCosName.Create('Fl'));
    FilterArray.Add(TCosDictionary.Create);
    Stream.SetItem('Filter', FilterArray);

    Assert.WillRaise(
      procedure
      begin
        Stream.GetFilterNames;
      end,
      EPdfParseException);
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestDecodeUntilImageFilter;
begin
  const Stream = NewStream(TFilterTestSupport.Compress(TFilterTestSupport.AsciiBytes('jpeg bytes')), ['FlateDecode', 'DCTDecode']);
  try
    const Outcome = Stream.DecodeUntilImageFilter;

    Assert.AreEqual('jpeg bytes', TFilterTestSupport.AsciiString(Outcome.Data));
    Assert.AreEqual('DCTDecode', string.Join(',', Outcome.RemainingFilters));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestDecodeUntilImageFilterWithoutImageFilter;
begin
  const Stream = NewStream(TFilterTestSupport.Compress(TFilterTestSupport.AsciiBytes('text')), ['Fl']);
  try
    const Outcome = Stream.DecodeUntilImageFilter;

    Assert.AreEqual('text', TFilterTestSupport.AsciiString(Outcome.Data));
    Assert.AreEqual<Integer>(0, Length(Outcome.RemainingFilters));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestDecodeUntilImageFilterAsFirstFilter;
begin
  const Stream = NewStream(ToHexText('raw'), ['DCT', 'Fl']);
  try
    const Outcome = Stream.DecodeUntilImageFilter;

    Assert.AreEqual('raw', TFilterTestSupport.AsciiString(Outcome.Data));
    Assert.AreEqual('DCT,Fl', string.Join(',', Outcome.RemainingFilters));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestCreateDecodedStreamRaisesOnImageFilter;
begin
  const Stream = NewStream(TFilterTestSupport.Compress(ToHexText('x')), ['FlateDecode', 'DCTDecode']);
  try
    Assert.WillRaise(
      procedure
      begin
        Stream.CreateDecodedStream.Free;
      end,
      EPdfUnsupportedFeatureException);
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestCreateDecodedStreamRaisesOnUnknownFilter;
begin
  const Stream = NewStream(ToHexText('x'), ['NoSuchDecode']);
  try
    Assert.WillRaise(
      procedure
      begin
        Stream.CreateDecodedStream.Free;
      end,
      EPdfUnsupportedFeatureException);
    Assert.WillRaise(
      procedure
      begin
        Stream.DecodeUntilImageFilter;
      end,
      EPdfUnsupportedFeatureException);
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestDuplicateFiltersAreAppliedOnce;
begin
  const Stream = NewStream(TFilterTestSupport.Compress(TFilterTestSupport.AsciiBytes('once')), ['Fl', 'FlateDecode']);
  try
    Assert.AreEqual('once', TFilterTestSupport.AsciiString(Decoded(Stream)));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestLimitComesFromTheDocument;
begin
  var Options := TPdfLoadOptions.Default;
  Options.MaxDecodedStreamSize := 100;
  const Document = TCosDocument.Create(TRandomAccessRead.FromBytes(nil), Options);
  var Data: TBytes;
  SetLength(Data, 1000);
  const Stream = NewStream(TFilterTestSupport.Compress(Data), ['Fl']);
  try
    Stream.Document := Document;
    Assert.WillRaise(
      procedure
      begin
        Stream.CreateDecodedStream.Free;
      end,
      EPdfLimitExceededException);
    Assert.WillRaise(
      procedure
      begin
        Stream.DecodeUntilImageFilter;
      end,
      EPdfLimitExceededException);
  finally
    Stream.Free;
    Document.Free;
  end;
end;

procedure TCosStreamTests.TestDefaultLimitWithoutDocument;
begin
  var Data: TBytes;
  SetLength(Data, 100000);
  const Stream = NewStream(TFilterTestSupport.Compress(Data), ['Fl']);
  try
    Assert.AreEqual<Integer>(100000, Length(Decoded(Stream)));
  finally
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestDocumentLogReceivesFilterProblems;
begin
  var Lines := 0;
  var Options := TPdfLoadOptions.Default;
  Options.OnLog :=
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      Inc(Lines);
    end;
  const Document = TCosDocument.Create(TRandomAccessRead.FromBytes(nil), Options);
  const Garbage: TBytes = [$78, $9C, $FF, $FF, $FF];
  const Stream = NewStream(Garbage, ['Fl']);
  try
    Stream.Document := Document;

    Assert.AreEqual<Integer>(0, Length(Decoded(Stream)));
    Assert.AreEqual(1, Lines);
  finally
    Stream.Free;
    Document.Free;
  end;
end;

procedure TCosStreamTests.TestDocumentMustBeACosDocument;
begin
  const Stream = NewStream(nil, []);
  const NotADocument = TObject.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Stream.Document := NotADocument;
      end,
      EArgumentException);
  finally
    NotADocument.Free;
    Stream.Free;
  end;
end;

procedure TCosStreamTests.TestCryptFilterWithIdentityInAChain;
begin
  const Stream = NewStream(TFilterTestSupport.Compress(TFilterTestSupport.AsciiBytes('data')), ['Crypt', 'Fl']);
  try
    Assert.AreEqual('data', TFilterTestSupport.AsciiString(Decoded(Stream)));
  finally
    Stream.Free;
  end;
end;

end.
