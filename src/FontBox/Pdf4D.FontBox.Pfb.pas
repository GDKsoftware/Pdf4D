// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/pfb/PfbParser.java (3.0.8)
unit Pdf4D.FontBox.Pfb;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  // Splits a PFB file (Printer Font Binary) into the clear text part and the binary part of a Type 1 font
  TPfbParser = class
  private
    FSegment1: TBytes;
    FSegment2: TBytes;

    class function ReadSegmentSize(const Data: TBytes; const Position: Integer): Integer; static;
    class function ContainsClearToMark(const Segment: TBytes): Boolean; static;
    class function Concatenate(const Segments: TList<TBytes>; const Types: TList<Integer>; const SegmentType: Integer;
                               const SkipIndex: Integer): TBytes; static;

    procedure ParsePfb(const Data: TBytes);

  public
    // Raises EPdfParseException for a missing header or marker, an unknown record type and a segment that does not fit
    constructor Create(const Data: TBytes);

    // All ASCII segments in file order, without a closing cleartomark segment
    property Segment1: TBytes read FSegment1;
    // All binary segments in file order
    property Segment2: TBytes read FSegment2;
  end;

implementation

uses
  Pdf4D.Common.Defines;

const
  HeaderLength = 18;
  StartMarker = $80;
  AsciiMarker = 1;
  BinaryMarker = 2;
  EofMarker = 3;
  SizeFieldLength = 4;
  MaxClearToMarkLength = 600;
  ClearToMark: array[0..10] of Byte = (Ord('c'), Ord('l'), Ord('e'), Ord('a'), Ord('r'), Ord('t'), Ord('o'), Ord('m'),
                                       Ord('a'), Ord('r'), Ord('k'));

{ TPfbParser }

constructor TPfbParser.Create(const Data: TBytes);
begin
  inherited Create;
  ParsePfb(Data);
end;

class function TPfbParser.ReadSegmentSize(const Data: TBytes; const Position: Integer): Integer;
begin
  const Remaining = Length(Data) - Position;
  if Remaining < SizeFieldLength then
  begin
    raise EPdfParseException.Create('PFB record size is cut off');
  end;

  // Little endian; the top byte decides the sign, as with the signed int of PDFBox
  const Size = Int64(Data[Position]) or (Int64(Data[Position + 1]) shl 8) or (Int64(Data[Position + 2]) shl 16) or
               (Int64(Data[Position + 3]) shl 24);
  const IsNegative = (Size > High(Integer));
  if IsNegative then
  begin
    raise EPdfParseException.CreateFmt('PFB record size %d is negative', [Size - (Int64(1) shl 32)]);
  end;
  Result := Integer(Size);
end;

class function TPfbParser.ContainsClearToMark(const Segment: TBytes): Boolean;
begin
  Result := False;
  for var Start := 0 to Length(Segment) - Length(ClearToMark) do
  begin
    var Matches := True;
    for var Offset := 0 to High(ClearToMark) do
    begin
      if Segment[Start + Offset] <> ClearToMark[Offset] then
      begin
        Matches := False;
        Break;
      end;
    end;
    if Matches then
    begin
      Exit(True);
    end;
  end;
end;

class function TPfbParser.Concatenate(const Segments: TList<TBytes>; const Types: TList<Integer>; const SegmentType: Integer;
                                      const SkipIndex: Integer): TBytes;
begin
  var Total := 0;
  for var Index := 0 to Segments.Count - 1 do
  begin
    const IsWanted = ((Types[Index] = SegmentType) and (Index <> SkipIndex));
    if IsWanted then
    begin
      Inc(Total, Length(Segments[Index]));
    end;
  end;

  SetLength(Result, Total);
  var Position := 0;
  for var Index := 0 to Segments.Count - 1 do
  begin
    const IsWanted = ((Types[Index] = SegmentType) and (Index <> SkipIndex));
    if IsWanted and (Length(Segments[Index]) > 0) then
    begin
      Move(Segments[Index][0], Result[Position], Length(Segments[Index]));
      Inc(Position, Length(Segments[Index]));
    end;
  end;
end;

procedure TPfbParser.ParsePfb(const Data: TBytes);
begin
  if Length(Data) < HeaderLength then
  begin
    raise EPdfParseException.Create('PFB header missing');
  end;

  const Types = TList<Integer>.Create;
  const Segments = TList<TBytes>.Create;
  try
    var Position := 0;
    var Total: Int64 := 0;
    while True do
    begin
      const AtEnd = (Position >= Length(Data));
      if AtEnd and (Total > 0) then
      begin
        Break;
      end;
      if AtEnd or (Data[Position] <> StartMarker) then
      begin
        raise EPdfParseException.Create('PFB start marker missing');
      end;
      Inc(Position);

      if Position >= Length(Data) then
      begin
        raise EPdfParseException.Create('Incorrect PFB record type: -1');
      end;
      const RecordType = Data[Position];
      Inc(Position);
      if RecordType = EofMarker then
      begin
        Break;
      end;
      if (RecordType <> AsciiMarker) and (RecordType <> BinaryMarker) then
      begin
        raise EPdfParseException.CreateFmt('Incorrect PFB record type: %d', [RecordType]);
      end;

      const Size = ReadSegmentSize(Data, Position);
      Inc(Position, SizeFieldLength);
      if Size > Length(Data) - Position then
      begin
        raise EPdfParseException.CreateFmt('PFB record size %d is larger than the rest of the input', [Size]);
      end;

      var Segment: TBytes;
      SetLength(Segment, Size);
      if Size > 0 then
      begin
        Move(Data[Position], Segment[0], Size);
      end;
      Inc(Position, Size);
      Inc(Total, Size);
      Types.Add(RecordType);
      Segments.Add(Segment);
    end;

    // A closing ASCII segment with cleartomark (the zeros and the cleartomark operator) is not part of segment 1
    var SkipIndex := -1;
    const LastIndex = Segments.Count - 1;
    const LastIsClearToMark = ((LastIndex >= 0) and (Types[LastIndex] = AsciiMarker) and
                               (Length(Segments[LastIndex]) < MaxClearToMarkLength) and
                               ContainsClearToMark(Segments[LastIndex]));
    if LastIsClearToMark then
    begin
      SkipIndex := LastIndex;
    end;

    FSegment1 := Concatenate(Segments, Types, AsciiMarker, SkipIndex);
    FSegment2 := Concatenate(Segments, Types, BinaryMarker, -1);
  finally
    Segments.Free;
    Types.Free;
  end;
end;

end.
