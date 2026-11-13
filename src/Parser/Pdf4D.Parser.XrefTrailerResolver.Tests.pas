unit Pdf4D.Parser.XrefTrailerResolver.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Parser.XrefTrailerResolver;

type
  [TestFixture]
  TXrefTrailerResolverTests = class
  private
    FResolver: TXrefTrailerResolver;
    FLog: TPdfLog;
    FLogLines: TList<string>;

    function TrailerWith(const Size: Integer; const Prev: Int64): TCosDictionary;
    function HasLogLine(const Fragment: string): Boolean;

  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestLaterSectionOverridesEarlierEntries;

    [Test]
    procedure TestFirstEntryOfAKeyWinsWithinASection;

    [Test]
    procedure TestTrailerEntriesOfNewerSectionsWin;

    [Test]
    procedure TestEntryBeforeAnySectionIsIgnored;

    [Test]
    procedure TestUnknownStartxrefUsesAllSectionsInOrder;

    [Test]
    procedure TestPrevLoopBetweenSectionsEnds;

    [Test]
    procedure TestSectionNotInTheChainIsNotUsed;

    [Test]
    procedure TestContainedObjectNumbers;

    [Test]
    procedure TestResolvedValuesRaiseBeforeSetStartxref;

    [Test]
    procedure TestSetStartxrefTwiceIsIgnored;

    [Test]
    procedure TestResetClearsTheResolvedState;

    [Test]
    procedure TestFirstAndLastTrailer;

    [Test]
    procedure TestSectionAtTheSamePositionReplacesTheOldOne;

    [Test]
    procedure TestTypeOfTheResolvedChainIsTheTypeOfTheLastSection;
  end;

implementation

uses
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.ObjectKey;

{ TXrefTrailerResolverTests }

procedure TXrefTrailerResolverTests.Setup;
begin
  FLogLines := TList<string>.Create;
  FLog := TPdfLog.Create(
    procedure(const Level: TPdfLogLevel; const Message: string)
    begin
      FLogLines.Add(Message);
    end);
  FResolver := TXrefTrailerResolver.Create(FLog);
end;

procedure TXrefTrailerResolverTests.TearDown;
begin
  FResolver.Free;
  FLog.Free;
  FLogLines.Free;
end;

function TXrefTrailerResolverTests.TrailerWith(const Size: Integer; const Prev: Int64): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  Result.SetItem(TCosNames.Size, TCosInteger.Create(Size));
  if Prev >= 0 then
  begin
    Result.SetItem(TCosNames.Prev, TCosInteger.Create(Prev));
  end;
end;

function TXrefTrailerResolverTests.HasLogLine(const Fragment: string): Boolean;
begin
  Result := False;
  for var Line in FLogLines do
  begin
    if Line.Contains(Fragment) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TXrefTrailerResolverTests.TestLaterSectionOverridesEarlierEntries;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 10);
  FResolver.SetXref(TCosObjectKey.Make(2, 0), 20);
  FResolver.SetTrailer(TrailerWith(3, -1));
  FResolver.NextXrefObj(200, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(2, 0), 99);
  FResolver.SetTrailer(TrailerWith(3, 100));

  FResolver.SetStartxref(200);

  Assert.AreEqual<Int64>(10, FResolver.GetXrefTable[TCosObjectKey.Make(1, 0)]);
  Assert.AreEqual<Int64>(99, FResolver.GetXrefTable[TCosObjectKey.Make(2, 0)]);
end;

procedure TXrefTrailerResolverTests.TestFirstEntryOfAKeyWinsWithinASection;
begin
  FResolver.NextXrefObj(100, TXrefType.Stream);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 10);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 77);
  FResolver.SetTrailer(TrailerWith(2, -1));

  FResolver.SetStartxref(100);

  Assert.AreEqual<Int64>(10, FResolver.GetXrefTable[TCosObjectKey.Make(1, 0)]);
end;

procedure TXrefTrailerResolverTests.TestTrailerEntriesOfNewerSectionsWin;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  const Older = TrailerWith(3, -1);
  Older.SetItem('Only', TCosInteger.Create(5));
  FResolver.SetTrailer(Older);
  FResolver.NextXrefObj(200, TXrefType.Table);
  FResolver.SetTrailer(TrailerWith(8, 100));

  FResolver.SetStartxref(200);

  Assert.AreEqual(8, FResolver.GetTrailer.GetInt(TCosNames.Size, 0));
  Assert.AreEqual(5, FResolver.GetTrailer.GetInt('Only', 0));
end;

procedure TXrefTrailerResolverTests.TestEntryBeforeAnySectionIsIgnored;
begin
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 10);
  FResolver.SetTrailer(TrailerWith(1, -1));

  Assert.AreEqual(0, FResolver.GetTrailerCount);
  Assert.IsTrue(HasLogLine('XRef start was not signalled'));
end;

procedure TXrefTrailerResolverTests.TestUnknownStartxrefUsesAllSectionsInOrder;
begin
  FResolver.NextXrefObj(300, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 300);
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 100);
  FResolver.SetXref(TCosObjectKey.Make(2, 0), 101);

  FResolver.SetStartxref(5);

  Assert.AreEqual<Int64>(300, FResolver.GetXrefTable[TCosObjectKey.Make(1, 0)], 'ascending by position, so the highest is the newest');
  Assert.AreEqual<Int64>(101, FResolver.GetXrefTable[TCosObjectKey.Make(2, 0)]);
  Assert.IsTrue(HasLogLine('Did not found XRef object at specified startxref'));
end;

procedure TXrefTrailerResolverTests.TestPrevLoopBetweenSectionsEnds;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 1);
  FResolver.SetTrailer(TrailerWith(2, 200));
  FResolver.NextXrefObj(200, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(2, 0), 2);
  FResolver.SetTrailer(TrailerWith(2, 100));

  FResolver.SetStartxref(200);

  Assert.AreEqual(2, Integer(FResolver.GetXrefTable.Count));
end;

procedure TXrefTrailerResolverTests.TestSectionNotInTheChainIsNotUsed;
begin
  FResolver.NextXrefObj(50, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(9, 0), 9);
  FResolver.SetTrailer(TrailerWith(2, -1));
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 1);
  FResolver.SetTrailer(TrailerWith(2, 4000));

  FResolver.SetStartxref(100);

  Assert.AreEqual(1, Integer(FResolver.GetXrefTable.Count));
  Assert.IsTrue(HasLogLine('Did not found XRef object pointed to by ''Prev'''));
end;

procedure TXrefTrailerResolverTests.TestContainedObjectNumbers;
begin
  FResolver.NextXrefObj(100, TXrefType.Stream);
  FResolver.SetXref(TCosObjectKey.MakeInObjectStream(10, 0), -7);
  FResolver.SetXref(TCosObjectKey.MakeInObjectStream(11, 1), -7);
  FResolver.SetXref(TCosObjectKey.MakeInObjectStream(12, 0), -8);
  FResolver.SetXref(TCosObjectKey.Make(7, 0), 500);
  FResolver.SetTrailer(TrailerWith(13, -1));
  FResolver.SetStartxref(100);

  const InSeven = FResolver.GetContainedObjectNumbers(7);
  const InEight = FResolver.GetContainedObjectNumbers(8);
  const InNine = FResolver.GetContainedObjectNumbers(9);

  Assert.AreEqual(2, Integer(Length(InSeven)));
  Assert.AreEqual(1, Integer(Length(InEight)));
  Assert.AreEqual(12, Integer(InEight[0]));
  Assert.AreEqual(0, Integer(Length(InNine)));
end;

procedure TXrefTrailerResolverTests.TestResolvedValuesRaiseBeforeSetStartxref;
begin
  Assert.WillRaise(
    procedure
    begin
      FResolver.GetTrailer;
    end,
    EInvalidOpException);
  Assert.WillRaise(
    procedure
    begin
      FResolver.GetXrefTable;
    end,
    EInvalidOpException);
  Assert.WillRaise(
    procedure
    begin
      FResolver.GetCurrentTrailer;
    end,
    EInvalidOpException);
end;

procedure TXrefTrailerResolverTests.TestSetStartxrefTwiceIsIgnored;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 1);
  FResolver.SetStartxref(100);

  FResolver.SetStartxref(100);

  Assert.IsTrue(HasLogLine('only ones'));
  Assert.AreEqual(1, Integer(FResolver.GetXrefTable.Count));
end;

procedure TXrefTrailerResolverTests.TestResetClearsTheResolvedState;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 1);
  FResolver.SetStartxref(100);

  FResolver.Reset;

  Assert.IsFalse(FResolver.IsResolved);
  FResolver.SetStartxref(100);
  Assert.AreEqual(0, Integer(FResolver.GetXrefTable.Count), 'the tables of the sections are empty');
end;

procedure TXrefTrailerResolverTests.TestFirstAndLastTrailer;
begin
  var First: TCosDictionary;
  Assert.IsFalse(FResolver.TryGetFirstTrailer(First));

  FResolver.NextXrefObj(300, TXrefType.Table);
  FResolver.SetTrailer(TrailerWith(3, -1));
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetTrailer(TrailerWith(1, -1));

  var Last: TCosDictionary;
  Assert.IsTrue(FResolver.TryGetFirstTrailer(First));
  Assert.IsTrue(FResolver.TryGetLastTrailer(Last));
  Assert.AreEqual(1, First.GetInt(TCosNames.Size, 0));
  Assert.AreEqual(3, Last.GetInt(TCosNames.Size, 0));
  Assert.AreEqual(2, FResolver.GetTrailerCount);
end;

procedure TXrefTrailerResolverTests.TestSectionAtTheSamePositionReplacesTheOldOne;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(1, 0), 1);
  FResolver.SetTrailer(TrailerWith(1, -1));
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetXref(TCosObjectKey.Make(2, 0), 2);

  FResolver.SetStartxref(100);

  Assert.AreEqual(1, FResolver.GetTrailerCount);
  Assert.AreEqual(1, Integer(FResolver.GetXrefTable.Count));
end;

procedure TXrefTrailerResolverTests.TestTypeOfTheResolvedChainIsTheTypeOfTheLastSection;
begin
  FResolver.NextXrefObj(100, TXrefType.Table);
  FResolver.SetTrailer(TrailerWith(1, -1));
  FResolver.NextXrefObj(200, TXrefType.Stream);
  FResolver.SetTrailer(TrailerWith(1, 100));

  FResolver.SetStartxref(200);

  Assert.AreEqual<TXrefType>(TXrefType.Stream, FResolver.GetXrefType);
end;

end.
