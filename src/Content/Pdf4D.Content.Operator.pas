// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/Operator.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/contentstream/operator/OperatorName.java (3.0.8)
unit Pdf4D.Content.Operator;

interface

uses
  System.SysUtils,
  Pdf4D.Cos.Dictionary;

type
  // The names of the operators, as in OperatorName
  TOperatorNames = record
    const NonStrokingColor = 'sc';
    const NonStrokingColorN = 'scn';
    const NonStrokingRgb = 'rg';
    const NonStrokingGray = 'g';
    const NonStrokingCmyk = 'k';
    const NonStrokingColorSpace = 'cs';

    const StrokingColor = 'SC';
    const StrokingColorN = 'SCN';
    const StrokingColorRgb = 'RG';
    const StrokingColorGray = 'G';
    const StrokingColorCmyk = 'K';
    const StrokingColorSpace = 'CS';

    const BeginMarkedContentSeq = 'BDC';
    const BeginMarkedContent = 'BMC';
    const EndMarkedContent = 'EMC';
    const MarkedContentPointWithProps = 'DP';
    const MarkedContentPoint = 'MP';
    const DrawObject = 'Do';

    const Concat = 'cm';
    const Restore = 'Q';
    const Save = 'q';
    const SetFlatness = 'i';
    const SetGraphicsStateParams = 'gs';
    const SetLineCapStyle = 'J';
    const SetLineDashPattern = 'd';
    const SetLineJoinStyle = 'j';
    const SetLineMiterLimit = 'M';
    const SetLineWidth = 'w';
    const SetMatrix = 'Tm';
    const SetRenderingIntent = 'ri';

    const AppendRect = 're';
    const BeginInlineImage = 'BI';
    const BeginInlineImageData = 'ID';
    const EndInlineImage = 'EI';
    const ClipEvenOdd = 'W*';
    const ClipNonZero = 'W';
    const CloseAndStroke = 's';
    const CloseFillEvenOddAndStroke = 'b*';
    const CloseFillNonZeroAndStroke = 'b';
    const ClosePath = 'h';
    const CurveTo = 'c';
    const CurveToReplicateFinalPoint = 'y';
    const CurveToReplicateInitialPoint = 'v';
    const EndPath = 'n';
    const FillEvenOddAndStroke = 'B*';
    const FillEvenOdd = 'f*';
    const FillNonZeroAndStroke = 'B';
    const FillNonZero = 'f';
    const LegacyFillNonZero = 'F';
    const LineTo = 'l';
    const MoveTo = 'm';
    const ShadingFill = 'sh';
    const StrokePath = 'S';

    const BeginText = 'BT';
    const EndText = 'ET';
    const MoveText = 'Td';
    const MoveTextSetLeading = 'TD';
    const NextLine = 'T*';
    const SetCharSpacing = 'Tc';
    const SetFontAndSize = 'Tf';
    const SetTextHorizontalScaling = 'Tz';
    const SetTextLeading = 'TL';
    const SetTextRenderingMode = 'Tr';
    const SetTextRise = 'Ts';
    const SetWordSpacing = 'Tw';
    const ShowText = 'Tj';
    const ShowTextAdjusted = 'TJ';
    const ShowTextLine = '''';
    const ShowTextLineAndSpace = '"';

    const Type3D0 = 'd0';
    const Type3D1 = 'd1';

    const BeginCompatibilitySection = 'BX';
    const EndCompatibilitySection = 'EX';
  end;

  // An operator of a content stream. Unlike PDFBox there is no shared instance per name: the caller owns each one.
  TContentOperator = class
  private
    FName: string;
    FImageParameters: TCosDictionary;
    FImageData: TBytes;

    procedure SetImageParameters(const Value: TCosDictionary);

  public
    constructor Create(const Name: string);
    destructor Destroy; override;

    property Name: string read FName;
    // Only set on a BI operator. The operator owns the dictionary and frees a replaced one.
    property ImageParameters: TCosDictionary read FImageParameters write SetImageParameters;
    property ImageData: TBytes read FImageData write FImageData;
  end;

implementation

{ TContentOperator }

constructor TContentOperator.Create(const Name: string);
begin
  inherited Create;
  if Name.StartsWith('/') then
  begin
    raise EArgumentException.CreateFmt('Operators are not allowed to start with / ''%s''', [Name]);
  end;
  FName := Name;
end;

destructor TContentOperator.Destroy;
begin
  FImageParameters.Free;
  inherited;
end;

procedure TContentOperator.SetImageParameters(const Value: TCosDictionary);
begin
  if FImageParameters <> Value then
  begin
    FImageParameters.Free;
    FImageParameters := Value;
  end;
end;

end.
