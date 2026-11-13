// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/Predictor.java (3.0.8)
unit Pdf4D.Filter.Predictor;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Common.Log,
  Pdf4D.Cos.Dictionary;

type
  // Undoes the predictor row by row, like PredictorOutputStream. Write takes the predicted data; Finish decodes
  // a last incomplete row, filled up with zeros. Writes to Target, which is not owned.
  TPredictorStream = class(TStream)
  private
    FTarget: TStream;
    FLog: TPdfLog;
    FPredictor: Integer;
    FColors: Integer;
    FBitsPerComponent: Integer;
    FColumns: Integer;
    FRowLength: Integer;
    FPredictorPerRow: Boolean;
    FCurrentRow: TBytes;
    FLastRow: TBytes;
    FCurrentRowData: Integer;
    FPredictorRead: Boolean;
    FUnsupportedLogged: Boolean;

    procedure DecodeAndWriteRow;
    procedure FlipRows;

  public
    constructor Create(const Target: TStream; const Predictor, Colors, BitsPerComponent, Columns: Integer; const Log: TPdfLog);

    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;

    procedure Finish;
  end;

  TPredictor = class
  private
    const MaxRowLength = 64 * 1024 * 1024;
    const MaxColors = 32;
    const MaxBitsPerComponent = 32;

  private
    class procedure DecodeTiffRow(const Colors, BitsPerComponent, Columns: Integer; const ActLine: TBytes); static;
    class procedure DecodeTiffRowOf8Bits(const BytesPerPixel: Integer; const ActLine: TBytes); static;
    class procedure DecodeTiffRowOf16Bits(const BytesPerPixel: Integer; const ActLine: TBytes); static;
    class procedure DecodeTiffRowOf1Bit(const ActLine: TBytes); static;
    class procedure DecodeTiffRowOfSmallSamples(const Colors, BitsPerComponent, Columns: Integer; const ActLine: TBytes); static;
    class procedure DecodePaethRow(const BytesPerPixel: Integer; const ActLine, LastLine: TBytes); static;

  public
    class function IsTiffDepthSupported(const BitsPerComponent: Integer): Boolean; static;

    // The row of the predictor is decoded in place. LastLine is the previous decoded row, of the same length.
    class procedure DecodePredictorRow(const Predictor, Colors, BitsPerComponent, Columns: Integer; const ActLine, LastLine: TBytes); static;
    class function CalculateRowLength(const Colors, BitsPerComponent, Columns: Integer): Int64; static;
    class function GetBitSeq(const Value, StartBit, BitSize: Integer): Integer; static;
    class function CalcSetBitSeq(const Value, StartBit, BitSize, NewValue: Integer): Integer; static;

    // Port of Predictor.wrapPredictor. Parameters holds /Predictor, /Colors, /BitsPerComponent and /Columns.
    // Gives nil when there is no predictor to undo, otherwise a stream the caller owns, has to Finish and free.
    class function CreateDecodingStream(const Output: TStream; const Parameters: TCosDictionary; const Log: TPdfLog): TPredictorStream; static;

    // Decodes the predicted data of Input into Output
    class procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Log: TPdfLog = nil); static;
  end;

implementation

uses
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names;

{ TPredictor }

class function TPredictor.IsTiffDepthSupported(const BitsPerComponent: Integer): Boolean;
begin
  case BitsPerComponent of
    1, 2, 4, 8, 16: Result := True;
  else
    Result := False;
  end;
end;

class function TPredictor.CalculateRowLength(const Colors, BitsPerComponent, Columns: Integer): Int64;
begin
  const BitsPerPixel = Int64(Colors) * BitsPerComponent;
  Result := (Columns * BitsPerPixel + 7) div 8;
end;

class function TPredictor.GetBitSeq(const Value, StartBit, BitSize: Integer): Integer;
begin
  const Mask = (1 shl BitSize) - 1;
  Result := (Value shr StartBit) and Mask;
end;

class function TPredictor.CalcSetBitSeq(const Value, StartBit, BitSize, NewValue: Integer): Integer;
begin
  var Mask := (1 shl BitSize) - 1;
  const TruncatedValue = NewValue and Mask;
  Mask := not (Mask shl StartBit);
  Result := (Value and Mask) or (TruncatedValue shl StartBit);
end;

class procedure TPredictor.DecodePredictorRow(const Predictor, Colors, BitsPerComponent, Columns: Integer; const ActLine, LastLine: TBytes);
begin
  const BytesPerPixel = (Colors * BitsPerComponent + 7) div 8;
  const RowLength = Length(ActLine);

  case Predictor of
    2:
      DecodeTiffRow(Colors, BitsPerComponent, Columns, ActLine);
    11:
      for var Position := BytesPerPixel to RowLength - 1 do
      begin
        ActLine[Position] := Byte(ActLine[Position] + ActLine[Position - BytesPerPixel]);
      end;
    12:
      for var Position := 0 to RowLength - 1 do
      begin
        ActLine[Position] := Byte(ActLine[Position] + LastLine[Position]);
      end;
    13:
      for var Position := 0 to RowLength - 1 do
      begin
        var Left := 0;
        if Position - BytesPerPixel >= 0 then
        begin
          Left := ActLine[Position - BytesPerPixel];
        end;
        ActLine[Position] := Byte(ActLine[Position] + (Left + LastLine[Position]) div 2);
      end;
    14:
      DecodePaethRow(BytesPerPixel, ActLine, LastLine);
  end;
end;

class procedure TPredictor.DecodeTiffRow(const Colors, BitsPerComponent, Columns: Integer; const ActLine: TBytes);
begin
  const BytesPerPixel = (Colors * BitsPerComponent + 7) div 8;
  if BitsPerComponent = 8 then
  begin
    DecodeTiffRowOf8Bits(BytesPerPixel, ActLine);
  end
  else if BitsPerComponent = 16 then
  begin
    DecodeTiffRowOf16Bits(BytesPerPixel, ActLine);
  end
  else if (BitsPerComponent = 1) and (Colors = 1) then
  begin
    DecodeTiffRowOf1Bit(ActLine);
  end
  else if IsTiffDepthSupported(BitsPerComponent) then
  begin
    DecodeTiffRowOfSmallSamples(Colors, BitsPerComponent, Columns, ActLine);
  end;
end;

class procedure TPredictor.DecodeTiffRowOf8Bits(const BytesPerPixel: Integer; const ActLine: TBytes);
begin
  for var Position := BytesPerPixel to Length(ActLine) - 1 do
  begin
    ActLine[Position] := Byte(ActLine[Position] + ActLine[Position - BytesPerPixel]);
  end;
end;

class procedure TPredictor.DecodeTiffRowOf16Bits(const BytesPerPixel: Integer; const ActLine: TBytes);
begin
  var Position := BytesPerPixel;
  while Position < Length(ActLine) - 1 do
  begin
    const Sub = (Integer(ActLine[Position]) shl 8) + ActLine[Position + 1];
    const Left = (Integer(ActLine[Position - BytesPerPixel]) shl 8) + ActLine[Position - BytesPerPixel + 1];
    ActLine[Position] := Byte(((Sub + Left) shr 8) and $FF);
    ActLine[Position + 1] := Byte((Sub + Left) and $FF);
    Inc(Position, 2);
  end;
end;

class procedure TPredictor.DecodeTiffRowOf1Bit(const ActLine: TBytes);
begin
  for var Position := 0 to Length(ActLine) - 1 do
  begin
    for var Bit := 7 downto 0 do
    begin
      if (Position = 0) and (Bit = 7) then
      begin
        Continue;
      end;

      const Sub = (ActLine[Position] shr Bit) and 1;
      var Left: Integer;
      if Bit = 7 then
      begin
        Left := ActLine[Position - 1] and 1;
      end
      else
      begin
        Left := (ActLine[Position] shr (Bit + 1)) and 1;
      end;

      if ((Sub + Left) and 1) = 0 then
      begin
        ActLine[Position] := ActLine[Position] and not (1 shl Bit);
      end
      else
      begin
        ActLine[Position] := ActLine[Position] or (1 shl Bit);
      end;
    end;
  end;
end;

// Samples of 1, 2 and 4 bits never cross a byte border
class procedure TPredictor.DecodeTiffRowOfSmallSamples(const Colors, BitsPerComponent, Columns: Integer; const ActLine: TBytes);
begin
  for var Position := Colors to Columns * Colors - 1 do
  begin
    const BytePosSub = Position * BitsPerComponent div 8;
    const BitPosSub = 8 - Position * BitsPerComponent mod 8 - BitsPerComponent;
    const BytePosLeft = (Position - Colors) * BitsPerComponent div 8;
    const BitPosLeft = 8 - (Position - Colors) * BitsPerComponent mod 8 - BitsPerComponent;
    const Sub = GetBitSeq(ActLine[BytePosSub], BitPosSub, BitsPerComponent);
    const Left = GetBitSeq(ActLine[BytePosLeft], BitPosLeft, BitsPerComponent);
    ActLine[BytePosSub] := Byte(CalcSetBitSeq(ActLine[BytePosSub], BitPosSub, BitsPerComponent, Sub + Left));
  end;
end;

class procedure TPredictor.DecodePaethRow(const BytesPerPixel: Integer; const ActLine, LastLine: TBytes);
begin
  for var Position := 0 to Length(ActLine) - 1 do
  begin
    var A := 0;
    var C := 0;
    if Position - BytesPerPixel >= 0 then
    begin
      A := ActLine[Position - BytesPerPixel];
      C := LastLine[Position - BytesPerPixel];
    end;

    const B = LastLine[Position];
    const Estimate = A + B - C;
    const DistanceA = Abs(Estimate - A);
    const DistanceB = Abs(Estimate - B);
    const DistanceC = Abs(Estimate - C);
    if (DistanceA <= DistanceB) and (DistanceA <= DistanceC) then
    begin
      ActLine[Position] := Byte(ActLine[Position] + A);
    end
    else if DistanceB <= DistanceC then
    begin
      ActLine[Position] := Byte(ActLine[Position] + B);
    end
    else
    begin
      ActLine[Position] := Byte(ActLine[Position] + C);
    end;
  end;
end;

class function TPredictor.CreateDecodingStream(const Output: TStream; const Parameters: TCosDictionary; const Log: TPdfLog): TPredictorStream;
begin
  const Predictor = Parameters.GetInt(TCosNames.Predictor, -1);
  if Predictor <= 1 then
  begin
    Exit(nil);
  end;

  const Colors = Min(Parameters.GetInt(TCosNames.Colors, 1), MaxColors);
  const BitsPerComponent = Parameters.GetInt(TCosNames.BitsPerComponent, 8);
  const Columns = Parameters.GetInt(TCosNames.Columns, 1);
  Result := TPredictorStream.Create(Output, Predictor, Colors, BitsPerComponent, Columns, Log);
end;

class procedure TPredictor.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Log: TPdfLog);
begin
  const Decoding = CreateDecodingStream(Output, Parameters, Log);
  if not Assigned(Decoding) then
  begin
    Output.CopyFrom(Input, 0);
    Exit;
  end;

  try
    Decoding.CopyFrom(Input, 0);
    Decoding.Finish;
  finally
    Decoding.Free;
  end;
end;

{ TPredictorStream }

constructor TPredictorStream.Create(const Target: TStream; const Predictor, Colors, BitsPerComponent, Columns: Integer; const Log: TPdfLog);
begin
  inherited Create;
  FTarget := Target;
  FLog := Log;
  FPredictor := Predictor;
  FColors := Colors;
  FBitsPerComponent := BitsPerComponent;
  FColumns := Columns;

  // PDFBox only rejects a negative row length. A row of 0 bytes never advances, and parameters of zero or
  // below make no sense.
  const HasValidParameters = (Colors >= 1) and (Columns >= 1) and (BitsPerComponent >= 1) and (BitsPerComponent <= TPredictor.MaxBitsPerComponent);
  const RowLength = TPredictor.CalculateRowLength(Colors, BitsPerComponent, Columns);
  if not HasValidParameters or (RowLength > TPredictor.MaxRowLength) then
  begin
    raise EPdfParseException.CreateFmt('Unsupported predictor parameters: colors %d, bits per component %d, columns %d', [Colors, BitsPerComponent, Columns]);
  end;

  FRowLength := Integer(RowLength);
  FPredictorPerRow := (Predictor >= 10);
  SetLength(FCurrentRow, FRowLength);
  SetLength(FLastRow, FRowLength);
end;

function TPredictorStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise ENotSupportedException.Create('A predictor stream is write-only');
end;

function TPredictorStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  if (Offset = 0) and (Origin = TSeekOrigin.soCurrent) then
  begin
    Exit(0);
  end;

  raise ENotSupportedException.Create('A predictor stream cannot seek');
end;

function TPredictorStream.Write(const Buffer; Count: Longint): Longint;
begin
  const Bytes = PByte(@Buffer);
  var CurrentOffset := 0;
  while CurrentOffset < Count do
  begin
    if FPredictorPerRow and (FCurrentRowData = 0) and not FPredictorRead then
    begin
      // The first byte of a row is the PNG filter type, read as a signed byte like in PDFBox
      FPredictor := ShortInt(Bytes[CurrentOffset]) + 10;
      Inc(CurrentOffset);
      FPredictorRead := True;
    end
    else
    begin
      const ToRead = Min(FRowLength - FCurrentRowData, Count - CurrentOffset);
      Move(Bytes[CurrentOffset], FCurrentRow[FCurrentRowData], ToRead);
      Inc(FCurrentRowData, ToRead);
      Inc(CurrentOffset, ToRead);
      if FCurrentRowData = FRowLength then
      begin
        DecodeAndWriteRow;
      end;
    end;
  end;
  Result := Count;
end;

procedure TPredictorStream.Finish;
begin
  if FCurrentRowData > 0 then
  begin
    FillChar(FCurrentRow[FCurrentRowData], FRowLength - FCurrentRowData, 0);
    DecodeAndWriteRow;
  end;
end;

procedure TPredictorStream.DecodeAndWriteRow;
begin
  const IsUnsupported = (FPredictor = 2) and not TPredictor.IsTiffDepthSupported(FBitsPerComponent);
  if IsUnsupported and not FUnsupportedLogged and Assigned(FLog) then
  begin
    FLog.Warning('TIFF predictor with %d bits per component is not supported, the data is left as it is', [FBitsPerComponent]);
    FUnsupportedLogged := True;
  end;

  TPredictor.DecodePredictorRow(FPredictor, FColors, FBitsPerComponent, FColumns, FCurrentRow, FLastRow);
  FTarget.WriteBuffer(FCurrentRow[0], FRowLength);
  FlipRows;
end;

procedure TPredictorStream.FlipRows;
begin
  const Previous = FLastRow;
  FLastRow := FCurrentRow;
  FCurrentRow := Previous;
  FCurrentRowData := 0;
  FPredictorRead := False;
end;

end.
