// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSName.java (3.0.8)
unit Pdf4D.Cos.Name;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Base;

type
  TCosName = class(TCosBase)
  private
    FName: string;

  public
    // Port of COSName.getName: the bytes are UTF-8 when that decodes without loss, otherwise ISO-8859-1.
    class function DecodeBytes(const Bytes: TBytes): string; static;

    constructor Create(const Name: string);

    property Name: string read FName;
  end;

implementation

uses
  Pdf4D.Common.Utf8;

{ TCosName }

class function TCosName.DecodeBytes(const Bytes: TBytes): string;
begin
  var Decoded: string;
  if TPdfUtf8.TryDecodeStrict(Bytes, Decoded) and (Decoded.IndexOf(#$FFFD) < 0) then
  begin
    Exit(Decoded);
  end;

  SetLength(Result, Length(Bytes));
  for var Index := 0 to High(Bytes) do
  begin
    Result[Index + 1] := Char(Bytes[Index]);
  end;
end;

constructor TCosName.Create(const Name: string);
begin
  inherited Create;
  FName := Name;
end;

end.
