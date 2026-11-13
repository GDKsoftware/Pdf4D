// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSBase.java (3.0.8)
unit Pdf4D.Cos.Base;

interface

type
  TCosBase = class abstract
  private
    FDirect: Boolean;

  public
    property Direct: Boolean read FDirect write FDirect;
  end;

implementation

end.
