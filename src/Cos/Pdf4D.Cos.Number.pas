// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/cos/COSNumber.java (3.0.8)
unit Pdf4D.Cos.Number;

interface

uses
  Pdf4D.Cos.Base;

type
  TCosNumber = class abstract(TCosBase)
  public
    function FloatValue: Single; virtual; abstract;
    function IntValue: Integer; virtual; abstract;
    function LongValue: Int64; virtual; abstract;
  end;

implementation

end.
