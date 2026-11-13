// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.Factory.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFilterFactoryTests = class
  public
    [Test]
    procedure TestFactoryKnowsFiltersAndAbbreviations;

    [Test]
    procedure TestFactoryRejectsUnknownAndImageFilters;

    [Test]
    procedure TestIsImageFilter;

    [Test]
    procedure TestIdentityCryptFilterPassesDataThrough;

    [Test]
    procedure TestCryptFilterWithOtherNameIsUnsupported;

    [Test]
    procedure TestLimitedStreamRaisesBeyondTheLimit;

    [Test]
    procedure TestDecodeParmsAsArrayAndDpAbbreviation;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Filter.Base,
  Pdf4D.Filter.Factory,
  Pdf4D.Filter.LimitedStream,
  Pdf4D.Filter.Tests.Support;

{ TFilterFactoryTests }

procedure TFilterFactoryTests.TestFactoryKnowsFiltersAndAbbreviations;
begin
  const Names: TArray<string> = [
    'FlateDecode', 'Fl', 'LZWDecode', 'LZW', 'ASCIIHexDecode', 'AHx', 'ASCII85Decode', 'A85',
    'RunLengthDecode', 'RL', 'Crypt'];

  for var Name in Names do
  begin
    var Filter: TPdfFilter;
    Assert.IsTrue(TFilterFactory.TryGetFilter(Name, Filter), Name);
    Assert.IsNotNull(Filter, Name);
    Filter.Free;
  end;
end;

procedure TFilterFactoryTests.TestFactoryRejectsUnknownAndImageFilters;
begin
  const Names: TArray<string> = ['Nope', '', 'DCTDecode', 'DCT', 'JPXDecode', 'JBIG2Decode', 'CCITTFaxDecode', 'CCF'];

  for var Name in Names do
  begin
    var Filter: TPdfFilter;
    Assert.IsFalse(TFilterFactory.TryGetFilter(Name, Filter), Name);
    Assert.IsNull(Filter, Name);
  end;
end;

procedure TFilterFactoryTests.TestIsImageFilter;
begin
  Assert.IsTrue(TFilterFactory.IsImageFilter('DCTDecode'));
  Assert.IsTrue(TFilterFactory.IsImageFilter('DCT'));
  Assert.IsTrue(TFilterFactory.IsImageFilter('JPXDecode'));
  Assert.IsTrue(TFilterFactory.IsImageFilter('JBIG2Decode'));
  Assert.IsTrue(TFilterFactory.IsImageFilter('CCITTFaxDecode'));
  Assert.IsTrue(TFilterFactory.IsImageFilter('CCF'));
  Assert.IsFalse(TFilterFactory.IsImageFilter('FlateDecode'));
  Assert.IsFalse(TFilterFactory.IsImageFilter('Crypt'));
  Assert.IsFalse(TFilterFactory.IsImageFilter('Nope'));
end;

procedure TFilterFactoryTests.TestIdentityCryptFilterPassesDataThrough;
begin
  const Data: TBytes = [1, 2, 3];

  Assert.AreEqual('010203', TFilterTestSupport.ToHex(TFilterTestSupport.Decode('Crypt', Data)));

  const Parameters = TCosDictionary.Create;
  try
    Parameters.SetItem('Name', TCosName.Create('Identity'));
    Assert.AreEqual('010203', TFilterTestSupport.ToHex(TFilterTestSupport.Decode('Crypt', Data, Parameters)));
  finally
    Parameters.Free;
  end;
end;

procedure TFilterFactoryTests.TestCryptFilterWithOtherNameIsUnsupported;
begin
  const Parameters = TCosDictionary.Create;
  try
    Parameters.SetItem('Name', TCosName.Create('StdCF'));

    Assert.WillRaise(
      procedure
      begin
        TFilterTestSupport.Decode('Crypt', [1], Parameters);
      end,
      EPdfUnsupportedFeatureException);
  finally
    Parameters.Free;
  end;
end;

procedure TFilterFactoryTests.TestLimitedStreamRaisesBeyondTheLimit;
begin
  const Target = TBytesStream.Create;
  try
    const Limited = TLimitedStream.Create(Target, 5);
    try
      const Data: TBytes = [1, 2, 3];
      Limited.WriteBuffer(Data[0], 3);
      Limited.WriteBuffer(Data[0], 2);
      Assert.AreEqual(Int64(5), Limited.Position);

      Assert.WillRaise(
        procedure
        begin
          Limited.WriteBuffer(Data[0], 1);
        end,
        EPdfLimitExceededException);
      Assert.AreEqual<Int64>(5, Target.Size, 'nothing is written beyond the limit');
    finally
      Limited.Free;
    end;
  finally
    Target.Free;
  end;
end;

procedure TFilterFactoryTests.TestDecodeParmsAsArrayAndDpAbbreviation;
begin
  // Filter [/Fl /AHx], the parameters of the first filter in an array under the abbreviation /DP
  const Parameters = TCosDictionary.Create;
  try
    const Filters = TCosArray.Create;
    Filters.Add(TCosName.Create('Fl'));
    Filters.Add(TCosName.Create('AHx'));
    Parameters.SetItem('F', Filters);

    const AllParms = TCosArray.Create;
    const FirstParms = TCosDictionary.Create;
    FirstParms.SetItem('Predictor', TCosInteger.Create(12));
    FirstParms.SetItem('Columns', TCosInteger.Create(2));
    AllParms.Add(FirstParms);
    AllParms.Add(TCosDictionary.Create);
    Parameters.SetItem('DP', AllParms);

    const Rows: TBytes = [2, 1, 2, 2, 1, 1];
    const Decoded = TFilterTestSupport.Decode('Fl', TFilterTestSupport.Compress(Rows), Parameters);

    Assert.AreEqual('01020203', TFilterTestSupport.ToHex(Decoded));
  finally
    Parameters.Free;
  end;
end;

end.
