// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/filter/FlateFilter.java and FlateFilterDecoderStream.java (3.0.8)
unit Pdf4D.Filter.Flate;

interface

uses
  System.SysUtils,
  System.Classes,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Filter.Base;

type
  TFlateFilter = class(TPdfFilter)
  private
    const BlockSize = 64 * 1024;
    // Like PDFBox: the zlib header (2 bytes) is skipped and the checksum is ignored, so the data is raw deflate
    const ZlibHeaderLength = 2;
    const RawDeflateWindowBits = -15;

  private
    procedure InflateData(const Input, Output: TStream);

  public
    procedure Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer); override;
  end;

implementation

uses
  System.ZLib,
  Pdf4D.Filter.Predictor;

{ TFlateFilter }

procedure TFlateFilter.Decode(const Input, Output: TStream; const Parameters: TCosDictionary; const Index: Integer);
begin
  const DecodeParams = GetDecodeParams(Parameters, Index);
  const PredictorStream = TPredictor.CreateDecodingStream(Output, DecodeParams, Log);
  if not Assigned(PredictorStream) then
  begin
    InflateData(Input, Output);
    Exit;
  end;

  try
    InflateData(Input, PredictorStream);
    PredictorStream.Finish;
  finally
    PredictorStream.Free;
  end;
end;

// Reads the input and writes the output in blocks, so a stream that inflates enormously stops at the limit of the
// output without having been buffered. An error in the data keeps what was inflated up to there.
procedure TFlateFilter.InflateData(const Input, Output: TStream);
begin
  var InputBlock: TBytes;
  var OutputBlock: TBytes;
  SetLength(InputBlock, BlockSize);
  SetLength(OutputBlock, BlockSize);

  var Header: array[0..ZlibHeaderLength - 1] of Byte;
  Input.Read(Header, ZlibHeaderLength);

  var Stream: z_stream;
  FillChar(Stream, SizeOf(Stream), 0);
  Stream.zalloc := zlibAllocMem;
  Stream.zfree := zlibFreeMem;
  if inflateInit2(Stream, RawDeflateWindowBits) <> Z_OK then
  begin
    raise EZDecompressionError.Create('Cannot start the inflate of a Flate stream');
  end;

  try
    var Finished := False;
    var InputEnded := False;
    while not Finished do
    begin
      if (Stream.avail_in = 0) and not InputEnded then
      begin
        const Read = Input.Read(InputBlock[0], BlockSize);
        InputEnded := (Read = 0);
        Stream.next_in := @InputBlock[0];
        Stream.avail_in := Read;
      end;

      Stream.next_out := @OutputBlock[0];
      Stream.avail_out := BlockSize;
      const Status = inflate(Stream, Z_NO_FLUSH);

      const Produced = BlockSize - Stream.avail_out;
      if Produced > 0 then
      begin
        Output.WriteBuffer(OutputBlock[0], Produced);
      end;

      case Status of
        Z_OK:
          // When the data is cut off, inflate is called until it has given all it has
          Finished := InputEnded and (Produced = 0);
        Z_STREAM_END:
          Finished := True;
        Z_BUF_ERROR:
          // No progress is possible without more input
          Finished := InputEnded or (Stream.avail_in <> 0);
      else
        if Assigned(Log) then
        begin
          Log.Warning('FlateFilter: premature end of stream due to a data error (code %d)', [Status]);
        end;
        Finished := True;
      end;
    end;
  finally
    inflateEnd(Stream);
  end;
end;

end.
