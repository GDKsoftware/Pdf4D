unit Pdf4D.IO.RandomAccessRead.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRandomAccessReadTests = class
  public
    [Test]
    procedure TestReadPeekRewind;

    [Test]
    procedure TestSeekAndEof;

    [Test]
    procedure TestViewIsBounded;

    [Test]
    procedure TestBufferBoundary;

    [Test]
    procedure TestBlockReadAcrossBufferBoundary;

    [Test]
    procedure TestReadFullyReturnsRequestedBytes;

    [Test]
    procedure TestReadFullyPastEofRaises;

    [Test]
    procedure TestInvalidArgumentsRaise;

    [Test]
    procedure TestViewOfViewAndInvalidView;

    [Test]
    procedure TestFromFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Pdf4D.Common.Defines,
  Pdf4D.IO.RandomAccessRead;

const
  LargeSize = 70000;

function TextBytes(const Text: string): TBytes;
begin
  Result := TEncoding.ASCII.GetBytes(Text);
end;

function SequenceBytes(const Size: Integer): TBytes;
begin
  SetLength(Result, Size);
  for var Index := 0 to Size - 1 do
  begin
    Result[Index] := Byte((Index * 7) + (Index div 256));
  end;
end;

{ TRandomAccessReadTests }

procedure TRandomAccessReadTests.TestReadPeekRewind;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('%PDF-1.7'));
  try
    Assert.AreEqual(37, Reader.Read);
    Assert.AreEqual(80, Reader.Peek);
    Assert.AreEqual<Int64>(1, Reader.GetPosition);

    Reader.Rewind(1);

    Assert.AreEqual(37, Reader.Read);
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestSeekAndEof;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('%PDF-1.7'));
  try
    Assert.IsFalse(Reader.IsEOF);

    Reader.Seek(Reader.Length);

    Assert.IsTrue(Reader.IsEOF);
    Assert.AreEqual(-1, Reader.Read);
    Assert.AreEqual(-1, Reader.Peek);
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestViewIsBounded;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('0123456789'));
  try
    const View = Reader.CreateView(2, 3);
    try
      Assert.AreEqual<Int64>(3, View.Length);
      Assert.AreEqual('234', TEncoding.ASCII.GetString(View.ReadFully(3)));
      Assert.AreEqual(-1, View.Read);
      Assert.IsTrue(View.IsEOF);
    finally
      View.Free;
    end;
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestBufferBoundary;
begin
  const Source = SequenceBytes(LargeSize);
  const Reader = TRandomAccessRead.FromBytes(Source);
  try
    for var Index := 0 to LargeSize - 1 do
    begin
      const Actual = Reader.Read;
      if Actual <> Source[Index] then
      begin
        Assert.AreEqual<Integer>(Source[Index], Actual, Format('Byte at %d', [Index]));
      end;
    end;

    Assert.AreEqual(-1, Reader.Read);
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestBlockReadAcrossBufferBoundary;
begin
  const Source = SequenceBytes(LargeSize);
  const Reader = TRandomAccessRead.FromBytes(Source);
  try
    Reader.Seek(65000);
    var Buffer: TBytes;
    SetLength(Buffer, 3000);

    const ReadCount = Reader.Read(Buffer, 10, 2990);

    Assert.AreEqual(2990, ReadCount);
    for var Index := 0 to ReadCount - 1 do
    begin
      Assert.AreEqual<Byte>(Source[65000 + Index], Buffer[10 + Index]);
    end;

    Reader.Seek(LargeSize - 5);
    const TailCount = Reader.Read(Buffer, 0, 100);

    Assert.AreEqual(5, TailCount);
    Assert.AreEqual(-1, Reader.Read(Buffer, 0, 100));
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestReadFullyReturnsRequestedBytes;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('0123456789'));
  try
    Reader.Seek(4);

    const Actual = TEncoding.ASCII.GetString(Reader.ReadFully(4));

    Assert.AreEqual('4567', Actual);
    Assert.AreEqual<Int64>(8, Reader.GetPosition);
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestReadFullyPastEofRaises;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('0123'));
  try
    Reader.Seek(2);

    Assert.WillRaise(
      procedure
      begin
        Reader.ReadFully(3);
      end,
      EPdfParseException);
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestInvalidArgumentsRaise;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('0123'));
  try
    Reader.Read;

    Assert.WillRaise(
      procedure
      begin
        Reader.Seek(-1);
      end,
      EPdfParseException, 'negative seek');
    Assert.WillRaise(
      procedure
      begin
        Reader.Rewind(2);
      end,
      EPdfParseException, 'rewind before start');
    Assert.WillRaise(
      procedure
      begin
        var Buffer: TBytes;
        SetLength(Buffer, 2);
        Reader.Read(Buffer, 1, 2);
      end,
      EPdfParseException, 'range outside buffer');
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestViewOfViewAndInvalidView;
begin
  const Reader = TRandomAccessRead.FromBytes(TextBytes('0123456789'));
  try
    const Outer = Reader.CreateView(2, 6);
    try
      const Inner = Outer.CreateView(1, 2);
      try
        Assert.AreEqual('34', TEncoding.ASCII.GetString(Inner.ReadFully(2)));
        Assert.AreEqual(-1, Inner.Read);
      finally
        Inner.Free;
      end;

      Assert.WillRaise(
        procedure
        begin
          Outer.CreateView(4, 3);
        end,
        EPdfParseException, 'view beyond its parent');
    finally
      Outer.Free;
    end;
  finally
    Reader.Free;
  end;
end;

procedure TRandomAccessReadTests.TestFromFile;
begin
  const FileName = TPath.Combine(TPath.GetTempPath, 'Pdf4D.RandomAccessRead.Tests.bin');
  TFile.WriteAllBytes(FileName, TextBytes('%PDF-1.7'));
  try
    const Reader = TRandomAccessRead.FromFile(FileName);
    try
      Assert.AreEqual<Int64>(8, Reader.Length);
      Assert.AreEqual(37, Reader.Read);
    finally
      Reader.Free;
    end;
  finally
    TFile.Delete(FileName);
  end;
end;

end.
