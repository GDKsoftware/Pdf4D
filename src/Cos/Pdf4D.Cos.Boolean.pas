// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSBoolean.java (3.0.8)
unit Pdf4D.Cos.Boolean;

interface

uses
  Pdf4D.Cos.Base;

type
  TCosBoolean = class(TCosBase)
  private
    FValue: Boolean;

  public
    constructor Create(const Value: Boolean);

    property Value: Boolean read FValue;
  end;

implementation

{ TCosBoolean }

constructor TCosBoolean.Create(const Value: Boolean);
begin
  inherited Create;
  FValue := Value;
end;

end.
