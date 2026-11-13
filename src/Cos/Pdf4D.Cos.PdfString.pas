// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSString.java (3.0.8)
unit Pdf4D.Cos.PdfString;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base;

type
  TCosString = class(TCosBase)
  private
    FBytes: TBytes;
    FIsHex: Boolean;

    function HasBom(const First, Second: Byte): Boolean;

  public
    constructor Create(const Bytes: TBytes; const IsHex: Boolean);

    // Port of COSString.getString: a BOM selects UTF-16BE, UTF-16LE or (PDF 2.0) UTF-8, otherwise PDFDocEncoding.
    function GetString: string;

    // Writable so that decryption can replace the bytes
    property Bytes: TBytes read FBytes write FBytes;
    property IsHex: Boolean read FIsHex write FIsHex;
  end;

implementation

uses
  Pdf4D.Common.Utf8,
  Pdf4D.Cos.PdfDocEncoding;

{ TCosString }

constructor TCosString.Create(const Bytes: TBytes; const IsHex: Boolean);
begin
  inherited Create;
  FBytes := Copy(Bytes);
  FIsHex := IsHex;
end;

function TCosString.GetString: string;
begin
  if HasBom($FE, $FF) then
  begin
    Exit(TPdfUtf8.DecodeUtf16(FBytes, 2, True));
  end;

  // Not in the PDF specification, but PDFBox reads it
  if HasBom($FF, $FE) then
  begin
    Exit(TPdfUtf8.DecodeUtf16(FBytes, 2, False));
  end;

  if (Length(FBytes) >= 3) and (FBytes[0] = $EF) and (FBytes[1] = $BB) and (FBytes[2] = $BF) then
  begin
    Exit(TPdfUtf8.DecodeLenient(FBytes, 3));
  end;

  Result := TPdfDocEncoding.Decode(FBytes);
end;

function TCosString.HasBom(const First, Second: Byte): Boolean;
begin
  Result := (Length(FBytes) >= 2) and (FBytes[0] = First) and (FBytes[1] = Second);
end;

end.
