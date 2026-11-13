// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.ResourceData.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPdfResourceDataTests = class
  public
    [Test]
    procedure TestNameOf;

    [Test]
    procedure TestLoadRaisesForMissingResource;

    [Test]
    procedure TestGlyphListLoads;

    [Test]
    procedure TestAfmLoads;

    [Test]
    procedure TestCMapLoads;

    [Test]
    procedure TestLiberationSansLoads;

    [Test]
    procedure TestResourceHashesMatchCsv;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Hash,
  Pdf4D.Common.Defines,
  Pdf4D.Common.ResourceData,
  Pdf4D.Resources.GlyphList,
  Pdf4D.Resources.Afm,
  Pdf4D.Resources.CMap,
  Pdf4D.Resources.Fonts,
  Pdf4D.Tests.Corpus;

const
  ExpectedResourceCount: Integer = 111;
  CsvNameColumn = 0;
  CsvHashColumn = 2;
  CsvColumnCount: Integer = 4;

function AsText(const Data: TBytes): string;
begin
  Result := TEncoding.ASCII.GetString(Data);
end;

function CountLines(const Data: TBytes): Integer;
begin
  Result := 0;
  for var Value in Data do
  begin
    if Value = 10 then
    begin
      Inc(Result);
    end;
  end;
end;

{ TPdfResourceDataTests }

procedure TPdfResourceDataTests.TestNameOf;
begin
  Assert.AreEqual('PDF4D_CMAP_UNIGB_UCS2_H', TPdfResourceData.NameOf('CMAP', 'UniGB-UCS2-H'));
  Assert.AreEqual('PDF4D_AFM_HELVETICA_BOLDOBLIQUE', TPdfResourceData.NameOf('AFM', 'Helvetica-BoldOblique'));
end;

procedure TPdfResourceDataTests.TestLoadRaisesForMissingResource;
begin
  var Data: TBytes;

  Assert.IsFalse(TPdfResourceData.TryLoad('PDF4D_NO_SUCH_RESOURCE', Data));
  Assert.WillRaise(
    procedure
    begin
      TPdfResourceData.Load('PDF4D_NO_SUCH_RESOURCE');
    end,
    EPdfException);
end;

procedure TPdfResourceDataTests.TestGlyphListLoads;
begin
  const Data = TPdfGlyphListResources.Load('glyphlist');

  Assert.IsTrue(AsText(Data).Contains('fi;FB01'));
  Assert.AreEqual<Integer>(4327, CountLines(Data));
  Assert.IsTrue(Length(TPdfGlyphListResources.Load('zapfdingbats')) > 0);
  Assert.IsTrue(Length(TPdfGlyphListResources.Load('additional')) > 0);
end;

procedure TPdfResourceDataTests.TestAfmLoads;
begin
  Assert.IsTrue(AsText(TPdfAfmResources.Load('Helvetica')).Contains('C 32 ; WX 278 ; N space'));
  Assert.IsTrue(AsText(TPdfAfmResources.Load('MustRead')).Length > 0);
end;

procedure TPdfResourceDataTests.TestCMapLoads;
begin
  var Data: TBytes;

  Assert.IsTrue(TPdfCMapResources.TryLoad('Identity-H', Data));
  Assert.IsTrue(Length(Data) > 0);
  Assert.IsFalse(TPdfCMapResources.TryLoad('No-Such-CMap', Data));
end;

procedure TPdfResourceDataTests.TestLiberationSansLoads;
begin
  const Data = TPdfFontResources.LiberationSans;

  Assert.AreEqual<Integer>(410712, Length(Data));
  Assert.AreEqual<Byte>(0, Data[0]);
  Assert.AreEqual<Byte>(1, Data[1]);
  Assert.AreEqual<Byte>(0, Data[2]);
  Assert.AreEqual<Byte>(0, Data[3]);
end;

procedure TPdfResourceDataTests.TestResourceHashesMatchCsv;
begin
  const Folder = TPath.GetFullPath(TPath.Combine(TCorpus.Folder, '..' + PathDelim + '..' + PathDelim + 'src' + PathDelim + 'Resources'));
  const Rows = TFile.ReadAllLines(TPath.Combine(Folder, 'resources.csv'), TEncoding.UTF8);

  // The first row holds the column names
  Assert.AreEqual<Integer>(ExpectedResourceCount + 1, Length(Rows));
  for var Index := 1 to High(Rows) do
  begin
    const Columns = Rows[Index].Split([';']);
    Assert.AreEqual<Integer>(CsvColumnCount, Length(Columns), Rows[Index]);
    const Data = TPdfResourceData.Load(Columns[CsvNameColumn]);
    var Hash := THashSHA2.Create;
    Hash.Update(Data);
    Assert.AreEqual(Columns[CsvHashColumn], Hash.HashAsString, Columns[CsvNameColumn]);
  end;
end;

end.
