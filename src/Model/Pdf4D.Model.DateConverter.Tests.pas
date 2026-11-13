unit Pdf4D.Model.DateConverter.Tests;

interface

uses
  System.SysUtils,
  System.DateUtils,
  DUnitX.TestFramework,
  Pdf4D.Model.DateConverter;

type
  [TestFixture]
  TDateConverterTests = class
  private
    function Parse(const Text: string): string;

  public
    // The text, then the result of PDFBox 3.0.8 DateConverter.toCalendar written by toISO8601 (null for no date),
    // taken from TestDateUtil and from a run of PDFBox over more variants of the same formats
    [Test]
    procedure TestDateFormats;

    [Test]
    procedure TestEmptyAndMarkerOnlyTextIsNoDate;

    [Test]
    procedure TestTwoDigitYearsAroundToday;

    [Test]
    procedure TestValueAndOffset;

    [Test]
    procedure TestTimeZoneByNameWithDaylightSavingIsNotKnown;

    [Test]
    procedure TestToIso8601WithNegativeOffset;
  end;

implementation

const
  DateTable: array of string = [
    'D:20050512', '2005-05-12T00:00:00+00:00',
    'D:2005051223', '2005-05-12T23:00:00+00:00',
    'D:20050512235959+02''00''', '2005-05-12T23:59:59+02:00',
    '20050512235959Z', '2005-05-12T23:59:59+00:00',
    'D:20050526205258+01''00''', '2005-05-26T20:52:58+01:00',
    'D:05/12/2005', '2005-05-12T00:00:00+00:00',
    '5/12/2005 15:57:16', '2005-05-12T15:57:16+00:00',
    'D:2012', '2012-01-01T00:00:00+00:00',
    '2013', '2013-01-01T00:00:00+00:00',
    '2001-01-31T10:33+01:00  ', '2001-01-31T10:33:00+01:00',
    '2001-01-31T10:33.123+01:00', '2001-01-31T10:33:00+01:00',
    '9:47 5/12/2002', '2002-05-12T09:47:00+00:00',
    '200312172:2:3', '2003-12-17T02:02:03+00:00',
    '  20090319 200122', '2009-03-19T20:01:22+00:00',
    '20140401+0200', '2014-04-01T00:00:00+02:00',
    'Friday, January 11, 2115', '2115-01-11T00:00:00+00:00',
    'Monday, Jan 11, 1915', '1915-01-11T00:00:00+00:00',
    'Wed, January 11, 2215', '2215-01-11T00:00:00+00:00',
    ' Sun, January 11, 2015 ', '2015-01-11T00:00:00+00:00',
    '20190401 6:1:1 -1100', '2019-04-01T06:01:01-11:00',
    '26 May 2020 11:25:10', '2020-05-26T11:25:10+00:00',
    '26 May 2021 11:23', '2021-05-26T11:23:00+00:00',
    ' 2000 Feb 29 GMT + 11:30', '2000-02-29T00:00:00+11:30',
    'Tuesday, May 32 2000 11:27 UCT', 'null',
    '32 May 2000 11:25', 'null',
    '19921301 11:25', 'null',
    '19921001 11:60', 'null',
    '19920401 24:25', 'null',
    '20070430193647+713''00'' illegal tz hr', 'null',
    'nodigits', 'null',
    'Unknown', 'null',
    '333three digit year', 'null',
    '2000 Feb 29', '2000-02-29T00:00:00+00:00',
    ' 2000 Feb 29 UTC + 11:00', '2000-02-29T00:00:00+11:00',
    '2100 Feb 29 GMT+11', 'null',
    '2012 Feb 29 GMT+11', '2012-02-29T00:00:00+11:00',
    '2012 Feb 30 GMT+11', 'null',
    '1970 12 23:08', '1970-12-23T00:08:00+00:00',
    'Tuesday, 6 Jul 1971 5:22:1 PM', '1971-07-06T17:22:01+00:00',
    'Thu, July 6, 1972 5:22:1 pm', '1972-07-06T17:22:01+00:00',
    '7/6/1973 17:22:1', '1973-07-06T17:22:01+00:00',
    '7/6/1974', '1974-07-06T00:00:00+00:00',
    '1975-7-6T17:22:1-1000', '1975-07-06T17:22:01-10:00',
    '1976-7-6T17:22:1GMT-4', '1976-07-06T17:22:01-04:00',
    '2076-7-6T17:22:1EDT', 'null',
    '1960-7-6T17:22:1EST', '1960-07-06T17:22:01-05:00',
    'Wednesday, Jul 6, 1977', '1977-07-06T00:00:00+00:00',
    'Thu Jul 6, 1978 17:22:1', '1978-07-06T17:22:01+00:00',
    'Friday July 6 17:22:1 GMT+08:00 1979', '1979-07-06T17:22:01+08:00',
    'Sun, Jul 6, 1980 at 4:23pm', '1980-07-06T16:23:00+00:00',
    'Monday, July 6, 1981', '1981-07-06T00:00:00+00:00',
    '6 Jul 1982 17:22:1', '1982-07-06T17:22:01+00:00',
    '7/6/1984 17:22:01', '1984-07-06T17:22:01+00:00',
    '07/06/1986', '1986-07-06T00:00:00+00:00',
    '19910706 17:7:1 Z+0600', '1991-07-06T17:07:01+06:00',
    '19920706 17:07:01', '1992-07-06T17:07:01+00:00',
    '19930706+00''00''', '1993-07-06T00:00:00+00:00',
    '19970706-10''00''', '1997-07-06T00:00:00-10:00',
    '2073 12 25:08', '2073-12-25T00:08:00+00:00',
    'D:20160411160115+12''00''', '2016-04-11T16:01:15+12:00',
    'D:    ', 'null',
    'D:', 'null',
    'Mon Jan 01 12:00:00 GMT 2001', '2001-01-01T12:00:00+00:00',
    'Mon Jan 01 12:00:00 2001', '2001-01-01T12:00:00+00:00',
    'Mon Jan 02 12:00:00 2001', 'null',
    'Sat Jan 01 12:00:00 EST 2000', '2000-01-01T12:00:00-05:00',
    'Sun, Jul 7, 1980 at 4:23pm', 'null',
    '20050512235959-0800', '2005-05-12T23:59:59-08:00',
    '20050512235959+23''59''', '2005-05-12T23:59:59-00:01',
    'D:20050512235959+14''00''', '2005-05-12T23:59:59+14:00',
    'D:20050512235959+15''00''', '2005-05-12T23:59:59-09:00',
    'D:20050512235959-13''00''', '2005-05-12T23:59:59-13:00',
    '0000', 'null',
    'D:00000101', 'null',
    '2005-05-12 10:00:00', '2005-05-12T10:00:00+00:00',
    '2005-05-12T10:00:00.123456Z', '2005-05-12T10:00:00+00:00',
    'D:20050512235959 GMT', '2005-05-12T23:59:59+00:00',
    'D:2005051223595', '2005-05-12T23:59:05+00:00',
    '12/31/99', '1999-12-31T00:00:00+00:00',
    '1/2/3', '0003-01-02T00:00:00+00:00',
    '20050512T1030', '2005-05-12T10:30:00+00:00',
    'Thursday, Oct 17, 02', '2002-10-17T00:00:00+00:00',
    'Mon, 12 May 2005 10:00:00', 'null',
    'Mon, 12 May 05 10:00:00 +0200', 'null',
    '12 May 2005', 'null',
    'D:20050512  ', '2005-05-12T00:00:00+00:00',
    'D:20050512 x', 'null'
  ];

{ TDateConverterTests }

function TDateConverterTests.Parse(const Text: string): string;
begin
  var Value: TDateTime;
  var OffsetMinutes: Integer;
  if TDateConverter.TryParse(Text, Value, OffsetMinutes) then
  begin
    Result := TDateConverter.ToIso8601(Value, OffsetMinutes);
  end
  else
  begin
    Result := 'null';
  end;
end;

procedure TDateConverterTests.TestDateFormats;
begin
  Assert.AreEqual<Integer>(0, Length(DateTable) mod 2);
  for var Index := 0 to (Length(DateTable) div 2) - 1 do
  begin
    Assert.AreEqual(DateTable[Index * 2 + 1], Parse(DateTable[Index * 2]), Format('Text "%s"', [DateTable[Index * 2]]));
  end;
end;

procedure TDateConverterTests.TestEmptyAndMarkerOnlyTextIsNoDate;
begin
  Assert.AreEqual('null', Parse(''));
  Assert.AreEqual('null', Parse('   '));
  Assert.AreEqual('null', Parse('D:'));
  Assert.AreEqual('null', Parse('D:    '));
  Assert.AreEqual('null', Parse('  D:  '));
end;

procedure TDateConverterTests.TestTwoDigitYearsAroundToday;
begin
  // The two digit years run from 80 years before today to 19 years after it
  const Year = YearOf(Now);
  Assert.AreEqual(Format('%d-01-01T00:00:00+00:00', [Year - 79]), Parse(Format('1/1/%.2d 00:00:00', [(Year - 79) mod 100])));
  Assert.AreEqual(Format('%d-01-01T00:00:00+00:00', [Year + 19]), Parse(Format('1/1/%.2d', [(Year + 19) mod 100])));
end;

procedure TDateConverterTests.TestValueAndOffset;
begin
  var Value: TDateTime;
  var OffsetMinutes: Integer;
  Assert.IsTrue(TDateConverter.TryParse('D:20050526205258+01''00''', Value, OffsetMinutes));
  Assert.AreEqual(60, OffsetMinutes);
  Assert.AreEqual<TDateTime>(EncodeDateTime(2005, 5, 26, 20, 52, 58, 0), Value);

  Assert.IsTrue(TDateConverter.TryParse('20180401-02''30''', Value, OffsetMinutes));
  Assert.AreEqual(-150, OffsetMinutes);
end;

procedure TDateConverterTests.TestTimeZoneByNameWithDaylightSavingIsNotKnown;
begin
  // Java knows these by a time zone database, here only the zones without daylight saving time are known
  Assert.AreEqual('null', Parse('Sat Jan 01 12:00:00 CST 2000'));
  Assert.AreEqual('2000-01-01T12:00:00-07:00', Parse('Sat Jan 01 12:00:00 MST 2000'));
end;

procedure TDateConverterTests.TestToIso8601WithNegativeOffset;
begin
  Assert.AreEqual('2018-04-01T00:00:00-02:30', TDateConverter.ToIso8601(EncodeDateTime(2018, 4, 1, 0, 0, 0, 0), -150));
  Assert.AreEqual('0003-01-02T04:05:06+00:00', TDateConverter.ToIso8601(EncodeDateTime(3, 1, 2, 4, 5, 6, 0), 0));
end;


end.
