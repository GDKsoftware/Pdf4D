// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Filter.Predictor.Tests;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Pdf4D.Cos.Dictionary;

type
  [TestFixture]
  TPredictorTests = class
  private
    function DecodeFlateWithPredictor(const Predicted: TBytes; const Columns: Integer; const Limit: Int64): TBytes;
    function Decode(const Predicted: TBytes; const Predictor, Colors, BitsPerComponent, Columns: Integer): string;
    function NewParameters(const Predictor, Colors, BitsPerComponent, Columns: Integer): TCosDictionary;

  public
    [Test]
    procedure TestGetBitSeq;

    [Test]
    procedure TestCalcSetBitSeq;

    [Test]
    procedure TestPngUpPredictor;

    [Test]
    procedure TestPngSubPredictor;

    [Test]
    procedure TestPngAveragePredictor;

    [Test]
    procedure TestPngPaethPredictor;

    [Test]
    procedure TestPngPredictorPerRowChangesTheFilter;

    [Test]
    procedure TestTiffPredictorOf8Bits;

    [Test]
    procedure TestTiffPredictorOf16Bits;

    [Test]
    procedure TestTiffPredictorOf4Bits;

    [Test]
    procedure TestIncompleteLastRowIsPaddedWithZeros;

    [Test]
    procedure TestNoPredictorCopiesTheData;

    [Test]
    procedure TestZeroColumnsRaises;

    [Test]
    procedure TestHugeRowLengthRaises;

    [Test]
    procedure TestUnsupportedTiffDepthLeavesDataAsItIs;

    [Test]
    procedure TestPredictorOutputRaisesLimitExceeded;

    [Test]
    procedure TestPredictorRowLongerThanTheLimitRaises;
  end;

implementation

uses
  System.Classes,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Integer,
  Pdf4D.Cos.Name,
  Pdf4D.Filter.Predictor,
  Pdf4D.Filter.Tests.Support;

function TPredictorTests.NewParameters(const Predictor, Colors, BitsPerComponent, Columns: Integer): TCosDictionary;
begin
  Result := TCosDictionary.Create;
  Result.SetItem('Predictor', TCosInteger.Create(Predictor));
  Result.SetItem('Colors', TCosInteger.Create(Colors));
  Result.SetItem('BitsPerComponent', TCosInteger.Create(BitsPerComponent));
  Result.SetItem('Columns', TCosInteger.Create(Columns));
end;

function TPredictorTests.Decode(const Predicted: TBytes; const Predictor, Colors, BitsPerComponent, Columns: Integer): string;
begin
  const Parameters = NewParameters(Predictor, Colors, BitsPerComponent, Columns);
  const Input = TBytesStream.Create(Predicted);
  const Output = TBytesStream.Create;
  try
    TPredictor.Decode(Input, Output, Parameters);
    Result := TFilterTestSupport.ToHex(Copy(Output.Bytes, 0, Output.Size));
  finally
    Output.Free;
    Input.Free;
    Parameters.Free;
  end;
end;

function TPredictorTests.DecodeFlateWithPredictor(const Predicted: TBytes; const Columns: Integer; const Limit: Int64): TBytes;
begin
  const StreamDictionary = TCosDictionary.Create;
  try
    StreamDictionary.SetItem('Filter', TCosName.Create('FlateDecode'));
    StreamDictionary.SetItem('DecodeParms', NewParameters(12, 1, 8, Columns));
    Result := TFilterTestSupport.Decode('FlateDecode', TFilterTestSupport.Compress(Predicted), StreamDictionary, nil, Limit);
  finally
    StreamDictionary.Free;
  end;
end;

procedure TPredictorTests.TestGetBitSeq;
begin
  Assert.AreEqual($FF, TPredictor.GetBitSeq($FF, 0, 8));
  Assert.AreEqual(0, TPredictor.GetBitSeq(0, 0, 8));
  Assert.AreEqual(1, TPredictor.GetBitSeq($FF, 0, 1));
  Assert.AreEqual(1, TPredictor.GetBitSeq($31, 0, 3));
  Assert.AreEqual($AA, TPredictor.GetBitSeq($AA, 0, 8));
  Assert.AreEqual(2, TPredictor.GetBitSeq($AA, 0, 2));
  Assert.AreEqual(1, TPredictor.GetBitSeq($AA, 1, 2));
  Assert.AreEqual(5, TPredictor.GetBitSeq($AA, 3, 3));
  Assert.AreEqual($55, TPredictor.GetBitSeq($AA, 1, 7));
  Assert.AreEqual($11, TPredictor.GetBitSeq($31, 0, 5));
  Assert.AreEqual(3, TPredictor.GetBitSeq($31, 4, 4));
  Assert.AreEqual(15, TPredictor.GetBitSeq($F0, 4, 4));
  Assert.AreEqual(0, TPredictor.GetBitSeq($F0, 0, 4));
end;

procedure TPredictorTests.TestCalcSetBitSeq;
begin
  Assert.AreEqual(0, TPredictor.CalcSetBitSeq($FF, 0, 8, 0));
  Assert.AreEqual(1, TPredictor.CalcSetBitSeq($FF, 0, 8, 1));
  Assert.AreEqual($FF, TPredictor.CalcSetBitSeq($FF, 0, 1, 1));
  Assert.AreEqual($FD, TPredictor.CalcSetBitSeq($FF, 0, 2, 1));
  Assert.AreEqual($F9, TPredictor.CalcSetBitSeq($FF, 0, 3, 1));
  Assert.AreEqual($F1, TPredictor.CalcSetBitSeq($FF, 0, 4, 1));
  Assert.AreEqual($E3, TPredictor.CalcSetBitSeq($FF, 1, 4, 1));
  Assert.AreEqual($02, TPredictor.CalcSetBitSeq(0, 1, 1, 1));
  Assert.AreEqual($7F, TPredictor.CalcSetBitSeq($FF, 7, 1, 0));
  Assert.AreEqual($80, TPredictor.CalcSetBitSeq(0, 7, 1, 1));
  Assert.AreEqual($30, TPredictor.CalcSetBitSeq(0, 3, 3, 6));
  Assert.AreEqual($C0, TPredictor.CalcSetBitSeq(0, 5, 3, 6));
  Assert.AreEqual($7E, TPredictor.CalcSetBitSeq($A5, 0, 8, $D9 + $A5));
  // The value is truncated to the size
  Assert.AreEqual($02, TPredictor.CalcSetBitSeq(0, 1, 1, 3));
end;

procedure TPredictorTests.TestPngUpPredictor;
begin
  // Two rows of 4 bytes, each with the filter type 2 (Up) in front
  Assert.AreEqual('0102030402030405', Decode([2, 1, 2, 3, 4, 2, 1, 1, 1, 1], 12, 1, 8, 4));
end;

procedure TPredictorTests.TestPngSubPredictor;
begin
  Assert.AreEqual('010306', Decode([1, 1, 2, 3], 15, 1, 8, 3));
  // The bytes of a pixel are added to the same colour of the pixel before: 3 colours
  Assert.AreEqual('010203050709', Decode([1, 1, 2, 3, 4, 5, 6], 15, 3, 8, 2));
end;

procedure TPredictorTests.TestPngAveragePredictor;
begin
  Assert.AreEqual('0A192A', Decode([3, 10, 20, 30], 15, 1, 8, 3));
end;

procedure TPredictorTests.TestPngPaethPredictor;
begin
  Assert.AreEqual('0A1E3C' + '0B1F3D', Decode([4, 10, 20, 30, 4, 1, 1, 1], 15, 1, 8, 3));
end;

procedure TPredictorTests.TestPngPredictorPerRowChangesTheFilter;
begin
  // None, then Up, then a filter type outside 0..4 that changes nothing
  Assert.AreEqual('0102' + '0203' + '0505', Decode([0, 1, 2, 2, 1, 1, 7, 5, 5], 10, 1, 8, 2));
end;

procedure TPredictorTests.TestTiffPredictorOf8Bits;
begin
  Assert.AreEqual('01020304' + '05060708', Decode([1, 1, 1, 1, 5, 1, 1, 1], 2, 1, 8, 4));
end;

procedure TPredictorTests.TestTiffPredictorOf16Bits;
begin
  // Samples 0x00FF and 0x0001: the sum is 0x0100
  Assert.AreEqual('00FF0100', Decode([$00, $FF, $00, $01], 2, 1, 16, 2));
end;

procedure TPredictorTests.TestTiffPredictorOf4Bits;
begin
  // Four samples of 4 bits per row: 1, 1, 1, 1 gives 1, 2, 3, 4
  Assert.AreEqual('1234', Decode([$11, $11], 2, 1, 4, 4));
end;

procedure TPredictorTests.TestIncompleteLastRowIsPaddedWithZeros;
begin
  Assert.AreEqual('01020304' + '02030304', Decode([2, 1, 2, 3, 4, 2, 1, 1], 12, 1, 8, 4));
end;

procedure TPredictorTests.TestNoPredictorCopiesTheData;
begin
  Assert.AreEqual('010203', Decode([1, 2, 3], 1, 1, 8, 4));
  Assert.AreEqual('010203', Decode([1, 2, 3], 0, 1, 8, 4));
end;

procedure TPredictorTests.TestZeroColumnsRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Decode([1, 2, 3], 12, 1, 8, 0);
    end,
    EPdfParseException);
  Assert.WillRaise(
    procedure
    begin
      Decode([1, 2, 3], 2, -1, -8, 4);
    end,
    EPdfParseException);
end;

procedure TPredictorTests.TestHugeRowLengthRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Decode([1, 2, 3], 12, 32, 32, MaxInt);
    end,
    EPdfParseException);
end;

procedure TPredictorTests.TestUnsupportedTiffDepthLeavesDataAsItIs;
begin
  Assert.AreEqual('01020304', Decode([1, 2, 3, 4], 2, 1, 3, 3));
end;

procedure TPredictorTests.TestPredictorOutputRaisesLimitExceeded;
begin
  // 1000 rows of a filter byte and 4 data bytes give 4000 bytes
  var Predicted: TBytes;
  SetLength(Predicted, 5000);
  for var Row := 0 to 999 do
  begin
    Predicted[Row * 5] := 2;
  end;

  Assert.WillRaise(
    procedure
    begin
      DecodeFlateWithPredictor(Predicted, 4, 100);
    end,
    EPdfLimitExceededException);
  Assert.AreEqual<Integer>(4000, Length(DecodeFlateWithPredictor(Predicted, 4, 4000)));
end;

procedure TPredictorTests.TestPredictorRowLongerThanTheLimitRaises;
begin
  // The row would be allocated twice from /Columns before any data arrives
  Assert.WillRaise(
    procedure
    begin
      DecodeFlateWithPredictor([2, 1, 2, 3], 50 * 1024 * 1024, 1000);
    end,
    EPdfLimitExceededException);
end;

end.