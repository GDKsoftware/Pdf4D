// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: the path part of fontbox/src/main/java/org/apache/fontbox/cff/Type1CharString.java and Type2CharString.java (3.0.8)
unit Pdf4D.FontBox.CharStringPath;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log,
  Pdf4D.Common.Path;

type
  // Turns a charstring into the outline of a glyph, in glyph space and with the limits of TCharStringWidth. A charstring that is
  // damaged gives the path up to the damage, with a warning in the log; the caller owns the path.
  TCharStringPath = class
  private
    class procedure WarnDamage(const Log: TPdfLog; const Reason: string); static;

  public
    // Seac components are found through Lookup (the glyph name of a StandardEncoding code to its charstring, empty when the font
    // has none); without a Lookup the accents of seac are left out.
    class function Type1Path(const CharString: TBytes; const Subrs: TArray<TBytes>; const Lookup: TFunc<string, TBytes>;
                             const Log: TPdfLog = nil): TPdfPath; static;
    // The deprecated seac form of endchar is not supported: the glyph has no accent then
    class function Type2Path(const CharString: TBytes; const GlobalSubrs, LocalSubrs: TArray<TBytes>;
                             const Log: TPdfLog = nil): TPdfPath; static;
  end;

implementation

uses
  System.Types,
  System.Generics.Collections,
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.CharStringReaders,
  Pdf4D.FontBox.CharStringWidth,
  Pdf4D.FontBox.Encoding;

const
  CodeClosePath = 9;
  CodeHHCurveTo = 27;
  CodeDotSection = EscapeBase + 0;
  CodeVStem3 = EscapeBase + 1;
  CodeHStem3 = EscapeBase + 2;
  CodeSeac = EscapeBase + 6;
  CodeSetCurrentPoint = EscapeBase + 33;

  // A seac component that has a seac of its own is no more than a charstring of a damaged font
  MaxSeacDepth = 4;

  Type1DamageMessage = 'Type 1 charstring is damaged, the path stops there: %s';
  Type2DamageMessage = 'Type 2 charstring is damaged, the path stops there: %s';
  MissingOperandMessage = 'The charstring operator takes an operand that is not there';

type
  // The path of a glyph with the behaviour of java.awt.geom.GeneralPath: a moveto after a moveto replaces it, and a closepath
  // after a closepath is dropped
  TGlyphOutline = class
  private
    FVerbs: TList<TPdfPathVerb>;
    FPoints: TList<TPointF>;

  public
    constructor Create;
    destructor Destroy; override;

    procedure MoveTo(const X, Y: Single);
    procedure LineTo(const X, Y: Single);
    procedure CubicTo(const X1, Y1, X2, Y2, X3, Y3: Single);
    procedure ClosePath;
    procedure Append(const Other: TGlyphOutline; const DeltaX, DeltaY: Double);

    function HasCurrentPoint: Boolean;
    function ToPath: TPdfPath;
  end;

  TType1Renderer = class
  private
    FOutline: TGlyphOutline;
    FSubrs: TArray<TBytes>;
    FLookup: TFunc<string, TBytes>;
    FLog: TPdfLog;
    FSeacDepth: Integer;
    FNumbers: TList<Double>;
    FCurrent: TPointF;
    FLeftSideBearing: TPointF;
    FIsFlex: Boolean;
    FFlexPoints: TList<TPointF>;

    function Number(const Index: Integer): Single;
    procedure Warn(const Fmt: string; const Args: array of const);

    procedure Interpret(const Items: TList<TCharStringItem>);
    procedure HandleCommand(const Code: Integer);
    procedure HandleMove(const Code: Integer);
    procedure HandleLine(const Code: Integer);
    procedure HandleCurve(const Code: Integer);
    procedure HandleSidebearing(const Code: Integer);
    procedure HandleDivision;

    procedure RMoveTo(const DeltaX, DeltaY: Single);
    procedure RLineTo(const DeltaX, DeltaY: Single);
    procedure RRCurveTo(const Dx1, Dy1, Dx2, Dy2, Dx3, Dy3: Single);
    procedure ClosePath;
    procedure CallOtherSubr(const OtherSubr: Integer);
    procedure EndFlex;
    procedure Seac(const Asb, Adx, Ady: Single; const BaseCode, AccentCode: Integer);
    procedure AppendComponent(const Code: Integer; const DeltaX, DeltaY: Double);

  public
    constructor Create(const Subrs: TArray<TBytes>; const Lookup: TFunc<string, TBytes>; const Log: TPdfLog;
                       const SeacDepth: Integer);
    destructor Destroy; override;

    // The caller owns the outline. A charstring that is damaged gives the outline up to the damage.
    class function Render(const CharString: TBytes; const Subrs: TArray<TBytes>; const Lookup: TFunc<string, TBytes>;
                          const Log: TPdfLog; const SeacDepth: Integer): TGlyphOutline; static;
    // The outline of a sequence that TType2Converter made. The accents of seac are left out.
    class function RenderConverted(const Items: TList<TCharStringItem>; const Log: TPdfLog): TGlyphOutline; static;
  end;

  // Type2CharString.convertType1ToType2: the Type 2 operators become the Type 1 operators that the renderer knows
  TType2Converter = class
  private
    FConverted: TList<TCharStringItem>;
    FPathCount: Integer;

    function CollapseDivisions(const Items: TList<TCharStringItem>): TList<TCharStringItem>;
    class function Operand(const Numbers: TArray<Double>; const Index: Integer): Double; static;
    class function Negated(const Value: Double): Double; static;

    procedure ConvertItems(const Items: TList<TCharStringItem>);
    procedure ConvertCommand(const Numbers: TArray<Double>; const Code: Integer);
    procedure ConvertMove(const Numbers: TArray<Double>; const Code: Integer);
    procedure ConvertEndChar(const Numbers: TArray<Double>);
    procedure ConvertLines(const Numbers: TArray<Double>; const Code: Integer);
    procedure ConvertCurves(const Numbers: TArray<Double>; const Code: Integer);
    procedure ConvertFlex(const Numbers: TArray<Double>; const Code: Integer);

    function ClearStack(const Numbers: TArray<Double>; const HasWidth: Boolean): TArray<Double>;
    procedure MarkPath;
    procedure CloseCharString2Path;
    procedure AddCommand(const Numbers: array of Double; const Code: Integer);
    procedure AddSplit(const Numbers: TArray<Double>; const First, Count, Size, Code: Integer);
    procedure AddAlternatingLine(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
    procedure AddAlternatingCurve(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
    procedure AddCurve(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
    procedure AddHFlex(const Numbers: TArray<Double>);
    procedure AddFlex(const Numbers: TArray<Double>);
    procedure AddHFlex1(const Numbers: TArray<Double>);
    procedure AddFlex1(const Numbers: TArray<Double>);
    procedure AddRCurveLine(const Numbers: TArray<Double>);
    procedure AddRLineCurve(const Numbers: TArray<Double>);

  public
    constructor Create;
    destructor Destroy; override;

    // What was converted before a damage stays in Converted
    procedure Convert(const Items: TList<TCharStringItem>);

    property Converted: TList<TCharStringItem> read FConverted;
  end;

{ TGlyphOutline }

constructor TGlyphOutline.Create;
begin
  inherited Create;
  FVerbs := TList<TPdfPathVerb>.Create;
  FPoints := TList<TPointF>.Create;
end;

destructor TGlyphOutline.Destroy;
begin
  FPoints.Free;
  FVerbs.Free;
  inherited;
end;

procedure TGlyphOutline.MoveTo(const X, Y: Single);
begin
  const FollowsMoveTo = ((FVerbs.Count > 0) and (FVerbs.Last = TPdfPathVerb.MoveTo));
  if FollowsMoveTo then
  begin
    FPoints[FPoints.Count - 1] := PointF(X, Y);
    Exit;
  end;
  FVerbs.Add(TPdfPathVerb.MoveTo);
  FPoints.Add(PointF(X, Y));
end;

procedure TGlyphOutline.LineTo(const X, Y: Single);
begin
  FVerbs.Add(TPdfPathVerb.LineTo);
  FPoints.Add(PointF(X, Y));
end;

procedure TGlyphOutline.CubicTo(const X1, Y1, X2, Y2, X3, Y3: Single);
begin
  FVerbs.Add(TPdfPathVerb.CubicTo);
  FPoints.Add(PointF(X1, Y1));
  FPoints.Add(PointF(X2, Y2));
  FPoints.Add(PointF(X3, Y3));
end;

procedure TGlyphOutline.ClosePath;
begin
  const FollowsClose = ((FVerbs.Count > 0) and (FVerbs.Last = TPdfPathVerb.Close));
  if (FVerbs.Count = 0) or (not FollowsClose) then
  begin
    FVerbs.Add(TPdfPathVerb.Close);
  end;
end;

// Path2D.append(PathIterator, false) of an iterator with a translation: the points are moved in double precision and
// rounded to float
procedure TGlyphOutline.Append(const Other: TGlyphOutline; const DeltaX, DeltaY: Double);
begin
  var PointIndex := 0;
  for var Verb in Other.FVerbs do
  begin
    case Verb of
      TPdfPathVerb.MoveTo:
        begin
          MoveTo(Single(Other.FPoints[PointIndex].X + DeltaX), Single(Other.FPoints[PointIndex].Y + DeltaY));
          Inc(PointIndex);
        end;
      TPdfPathVerb.LineTo:
        begin
          LineTo(Single(Other.FPoints[PointIndex].X + DeltaX), Single(Other.FPoints[PointIndex].Y + DeltaY));
          Inc(PointIndex);
        end;
      TPdfPathVerb.CubicTo:
        begin
          CubicTo(Single(Other.FPoints[PointIndex].X + DeltaX), Single(Other.FPoints[PointIndex].Y + DeltaY),
                  Single(Other.FPoints[PointIndex + 1].X + DeltaX), Single(Other.FPoints[PointIndex + 1].Y + DeltaY),
                  Single(Other.FPoints[PointIndex + 2].X + DeltaX), Single(Other.FPoints[PointIndex + 2].Y + DeltaY));
          Inc(PointIndex, 3);
        end;
      TPdfPathVerb.Close:
        ClosePath;
    else
      raise EPdfParseException.Create('The glyph outline has a segment that a charstring cannot make');
    end;
  end;
end;

function TGlyphOutline.HasCurrentPoint: Boolean;
begin
  Result := (FVerbs.Count > 0);
end;

function TGlyphOutline.ToPath: TPdfPath;
begin
  Result := TPdfPath.Create;
  try
    var PointIndex := 0;
    for var Verb in FVerbs do
    begin
      case Verb of
        TPdfPathVerb.MoveTo:
          begin
            Result.MoveTo(FPoints[PointIndex].X, FPoints[PointIndex].Y);
            Inc(PointIndex);
          end;
        TPdfPathVerb.LineTo:
          begin
            Result.LineTo(FPoints[PointIndex].X, FPoints[PointIndex].Y);
            Inc(PointIndex);
          end;
        TPdfPathVerb.CubicTo:
          begin
            Result.CubicTo(FPoints[PointIndex].X, FPoints[PointIndex].Y, FPoints[PointIndex + 1].X, FPoints[PointIndex + 1].Y,
                           FPoints[PointIndex + 2].X, FPoints[PointIndex + 2].Y);
            Inc(PointIndex, 3);
          end;
        TPdfPathVerb.Close:
          Result.ClosePath;
      else
        raise EPdfParseException.Create('The glyph outline has a segment that a charstring cannot make');
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ TType1Renderer }

constructor TType1Renderer.Create(const Subrs: TArray<TBytes>; const Lookup: TFunc<string, TBytes>; const Log: TPdfLog;
                                  const SeacDepth: Integer);
begin
  inherited Create;
  FOutline := TGlyphOutline.Create;
  FSubrs := Subrs;
  FLookup := Lookup;
  FLog := Log;
  FSeacDepth := SeacDepth;
  FNumbers := TList<Double>.Create;
  FFlexPoints := TList<TPointF>.Create;
end;

destructor TType1Renderer.Destroy;
begin
  FFlexPoints.Free;
  FNumbers.Free;
  FOutline.Free;
  inherited;
end;

class function TType1Renderer.Render(const CharString: TBytes; const Subrs: TArray<TBytes>; const Lookup: TFunc<string, TBytes>;
                                     const Log: TPdfLog; const SeacDepth: Integer): TGlyphOutline;
begin
  const Renderer = TType1Renderer.Create(Subrs, Lookup, Log, SeacDepth);
  try
    const Reader = TType1Reader.Create(Subrs, Log);
    try
      try
        Reader.ReadAll(CharString);
      except
        on Failure: EPdfParseException do
        begin
          Renderer.Warn(Type1DamageMessage, [Failure.Message]);
        end;
      end;
      Renderer.Interpret(Reader.Items);
    finally
      Reader.Free;
    end;
    Result := Renderer.FOutline;
    Renderer.FOutline := nil;
  finally
    Renderer.Free;
  end;
end;

function TType1Renderer.Number(const Index: Integer): Single;
begin
  Result := Single(FNumbers[Index]);
end;

procedure TType1Renderer.Warn(const Fmt: string; const Args: array of const);
begin
  if Assigned(FLog) then
  begin
    FLog.Warning(Fmt, Args);
  end;
end;

class function TType1Renderer.RenderConverted(const Items: TList<TCharStringItem>; const Log: TPdfLog): TGlyphOutline;
begin
  const Renderer = TType1Renderer.Create(nil, nil, Log, 0);
  try
    Renderer.Interpret(Items);
    Result := Renderer.FOutline;
    Renderer.FOutline := nil;
  finally
    Renderer.Free;
  end;
end;

procedure TType1Renderer.Interpret(const Items: TList<TCharStringItem>);
begin
  try
    for var Item in Items do
    begin
      if Item.IsCommand then
      begin
        HandleCommand(Item.Code);
        Continue;
      end;
      if FNumbers.Count >= MaxOperands then
      begin
        raise EPdfParseException.CreateFmt('The charstring has more than %d operands for one operator', [MaxOperands]);
      end;
      FNumbers.Add(Item.Value);
    end;
  except
    on Failure: EPdfParseException do
    begin
      Warn(Type1DamageMessage, [Failure.Message]);
    end;
  end;
end;

// Type1CharString.handleType1Command: an operator with too few operands does nothing, and the operands go after every operator
procedure TType1Renderer.HandleCommand(const Code: Integer);
begin
  case Code of
    CodeRMoveTo, CodeVMoveTo, CodeHMoveTo:
      HandleMove(Code);
    CodeRLineTo, CodeHLineTo, CodeVLineTo:
      HandleLine(Code);
    CodeRRCurveTo, CodeVHCurveTo, CodeHVCurveTo:
      HandleCurve(Code);
    CodeSBW, CodeHSBW:
      HandleSidebearing(Code);
    CodeClosePath:
      ClosePath;
    CodeSeac:
      if FNumbers.Count >= 5 then
      begin
        Seac(Number(0), Number(1), Number(2), TCFFNumber.ToInt(FNumbers[3]), TCFFNumber.ToInt(FNumbers[4]));
      end;
    CodeSetCurrentPoint:
      if FNumbers.Count >= 2 then
      begin
        FCurrent := PointF(Number(0), Number(1));
      end;
    CodeCallOtherSubr:
      if FNumbers.Count >= 1 then
      begin
        CallOtherSubr(TCFFNumber.ToInt(FNumbers[0]));
      end;
    CodeDiv:
      begin
        // The quotient stays among the operands
        HandleDivision;
        Exit;
      end;
    CodeHStem, CodeVStem, CodeHStem3, CodeVStem3, CodeDotSection, CodeEndChar:
      ;
    CodeReturn, CodeCallSubr:
      Warn('Unexpected charstring command %d', [Code]);
    CodePop:
      raise EPdfParseException.Create('A pop has no callothersubr before it');
  else
    Warn('Unknown charstring command %d', [Code]);
  end;
  FNumbers.Clear;
end;

procedure TType1Renderer.HandleMove(const Code: Integer);
begin
  if FNumbers.Count = 0 then
  begin
    Exit;
  end;
  var DeltaX: Single := 0;
  var DeltaY: Single := 0;
  case Code of
    CodeRMoveTo:
      begin
        if FNumbers.Count < 2 then
        begin
          Exit;
        end;
        DeltaX := Number(0);
        DeltaY := Number(1);
      end;
    CodeVMoveTo:
      DeltaY := Number(0);
    CodeHMoveTo:
      DeltaX := Number(0);
  end;
  if FIsFlex then
  begin
    FFlexPoints.Add(PointF(DeltaX, DeltaY));
  end
  else
  begin
    RMoveTo(DeltaX, DeltaY);
  end;
end;

procedure TType1Renderer.HandleLine(const Code: Integer);
begin
  if FNumbers.Count = 0 then
  begin
    Exit;
  end;
  case Code of
    CodeRLineTo:
      if FNumbers.Count >= 2 then
      begin
        RLineTo(Number(0), Number(1));
      end;
    CodeHLineTo:
      RLineTo(Number(0), 0);
    CodeVLineTo:
      RLineTo(0, Number(0));
  end;
end;

procedure TType1Renderer.HandleCurve(const Code: Integer);
begin
  case Code of
    CodeRRCurveTo:
      if FNumbers.Count >= 6 then
      begin
        RRCurveTo(Number(0), Number(1), Number(2), Number(3), Number(4), Number(5));
      end;
    CodeVHCurveTo:
      if FNumbers.Count >= 4 then
      begin
        RRCurveTo(0, Number(0), Number(1), Number(2), Number(3), 0);
      end;
    CodeHVCurveTo:
      if FNumbers.Count >= 4 then
      begin
        RRCurveTo(Number(0), 0, Number(1), Number(2), 0, Number(3));
      end;
  end;
end;

// The advance width is not needed for the path; the sidebearing is where the glyph starts
procedure TType1Renderer.HandleSidebearing(const Code: Integer);
begin
  if (Code = CodeSBW) and (FNumbers.Count >= 3) then
  begin
    FLeftSideBearing := PointF(Number(0), Number(1));
    FCurrent := FLeftSideBearing;
  end
  else if (Code = CodeHSBW) and (FNumbers.Count >= 2) then
  begin
    FLeftSideBearing := PointF(Number(0), 0);
    FCurrent := FLeftSideBearing;
  end;
end;

procedure TType1Renderer.HandleDivision;
begin
  if FNumbers.Count < 2 then
  begin
    FNumbers.Clear;
    Exit;
  end;
  const Divisor = Number(FNumbers.Count - 1);
  const Dividend = Number(FNumbers.Count - 2);
  FNumbers.Delete(FNumbers.Count - 1);
  FNumbers.Delete(FNumbers.Count - 1);
  FNumbers.Add(TCharStringReader.DivideSingles(Dividend, Divisor));
end;

procedure TType1Renderer.RMoveTo(const DeltaX, DeltaY: Single);
begin
  const X = Single(FCurrent.X + DeltaX);
  const Y = Single(FCurrent.Y + DeltaY);
  FOutline.MoveTo(X, Y);
  FCurrent := PointF(X, Y);
end;

procedure TType1Renderer.RLineTo(const DeltaX, DeltaY: Single);
begin
  const X = Single(FCurrent.X + DeltaX);
  const Y = Single(FCurrent.Y + DeltaY);
  if FOutline.HasCurrentPoint then
  begin
    FOutline.LineTo(X, Y);
  end
  else
  begin
    Warn('rlineto without initial moveto', []);
    FOutline.MoveTo(X, Y);
  end;
  FCurrent := PointF(X, Y);
end;

procedure TType1Renderer.RRCurveTo(const Dx1, Dy1, Dx2, Dy2, Dx3, Dy3: Single);
begin
  const X1 = Single(FCurrent.X + Dx1);
  const Y1 = Single(FCurrent.Y + Dy1);
  const X2 = Single(X1 + Dx2);
  const Y2 = Single(Y1 + Dy2);
  const X3 = Single(X2 + Dx3);
  const Y3 = Single(Y2 + Dy3);
  if FOutline.HasCurrentPoint then
  begin
    FOutline.CubicTo(X1, Y1, X2, Y2, X3, Y3);
  end
  else
  begin
    Warn('rrcurveto without initial moveto', []);
    FOutline.MoveTo(X3, Y3);
  end;
  FCurrent := PointF(X3, Y3);
end;

procedure TType1Renderer.ClosePath;
begin
  if FOutline.HasCurrentPoint then
  begin
    FOutline.ClosePath;
  end
  else
  begin
    Warn('closepath without initial moveto', []);
  end;
  FOutline.MoveTo(FCurrent.X, FCurrent.Y);
end;

procedure TType1Renderer.CallOtherSubr(const OtherSubr: Integer);
begin
  case OtherSubr of
    0:
      EndFlex;
    1:
      FIsFlex := True;
  else
    Warn('Invalid callothersubr parameter: %d', [OtherSubr]);
  end;
end;

// The seven flex points come as moves: the reference point, then the control and end points of two curves. Each is relative to
// the one before; the first curve starts at the current point.
procedure TType1Renderer.EndFlex;
begin
  FIsFlex := False;
  if FFlexPoints.Count < 7 then
  begin
    Warn('flex without moveto', []);
    Exit;
  end;

  const Reference = PointF(FCurrent.X + FFlexPoints[0].X, FCurrent.Y + FFlexPoints[0].Y);
  const FromReference = PointF(Reference.X + FFlexPoints[1].X, Reference.Y + FFlexPoints[1].Y);
  const First = PointF(FromReference.X - FCurrent.X, FromReference.Y - FCurrent.Y);

  RRCurveTo(First.X, First.Y, FFlexPoints[2].X, FFlexPoints[2].Y, FFlexPoints[3].X, FFlexPoints[3].Y);
  RRCurveTo(FFlexPoints[4].X, FFlexPoints[4].Y, FFlexPoints[5].X, FFlexPoints[5].Y, FFlexPoints[6].X, FFlexPoints[6].Y);
  FFlexPoints.Clear;
end;

procedure TType1Renderer.Seac(const Asb, Adx, Ady: Single; const BaseCode, AccentCode: Integer);
begin
  if (not Assigned(FLookup)) or (FSeacDepth >= MaxSeacDepth) then
  begin
    Warn('The accent of seac is left out', []);
    Exit;
  end;
  AppendComponent(BaseCode, 0, 0);
  AppendComponent(AccentCode, Double(FLeftSideBearing.X) + Adx - Asb, Double(FLeftSideBearing.Y) + Ady);
end;

procedure TType1Renderer.AppendComponent(const Code: Integer; const DeltaX, DeltaY: Double);
begin
  const GlyphName = TFontBoxStandardEncoding.Instance.GetName(Code);
  const CharString = FLookup(GlyphName);
  if Length(CharString) = 0 then
  begin
    Warn('Invalid seac character %s', [GlyphName]);
    Exit;
  end;

  const Component = TType1Renderer.Render(CharString, FSubrs, FLookup, FLog, FSeacDepth + 1);
  try
    FOutline.Append(Component, DeltaX, DeltaY);
  finally
    Component.Free;
  end;
end;

{ TType2Converter }

constructor TType2Converter.Create;
begin
  inherited Create;
  FConverted := TList<TCharStringItem>.Create;
end;

destructor TType2Converter.Destroy;
begin
  FConverted.Free;
  inherited;
end;

procedure TType2Converter.Convert(const Items: TList<TCharStringItem>);
begin
  const Collapsed = CollapseDivisions(Items);
  try
    ConvertItems(Collapsed);
  finally
    Collapsed.Free;
  end;
end;

// PDFBOX-5987: "num denom div" is replaced by its result. The two operands are looked up in the sequence as it was read.
function TType2Converter.CollapseDivisions(const Items: TList<TCharStringItem>): TList<TCharStringItem>;
begin
  Result := TList<TCharStringItem>.Create;
  try
    for var Index := 0 to Items.Count - 1 do
    begin
      const Item = Items[Index];
      const IsCollapsible = (Item.IsCommand and (Item.Code = CodeDiv) and (Index >= 2) and
                             (not Items[Index - 2].IsCommand) and (not Items[Index - 1].IsCommand));
      if not IsCollapsible then
      begin
        Result.Add(Item);
        Continue;
      end;

      var Quotient := Default(TCharStringItem);
      Quotient.Value := TCharStringReader.DivideSingles(Single(Items[Index - 2].Value), Single(Items[Index - 1].Value));
      Result.Delete(Result.Count - 1);
      Result.Delete(Result.Count - 1);
      Result.Add(Quotient);
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TType2Converter.Operand(const Numbers: TArray<Double>; const Index: Integer): Double;
begin
  if (Index < 0) or (Index >= Length(Numbers)) then
  begin
    raise EPdfParseException.Create(MissingOperandMessage);
  end;
  Result := Numbers[Index];
end;

class function TType2Converter.Negated(const Value: Double): Double;
begin
  Result := -Single(Value);
end;

procedure TType2Converter.ConvertItems(const Items: TList<TCharStringItem>);
begin
  const Pending = TList<Double>.Create;
  try
    for var Item in Items do
    begin
      if not Item.IsCommand then
      begin
        if Pending.Count >= MaxOperands then
        begin
          raise EPdfParseException.CreateFmt('The charstring has more than %d operands for one operator', [MaxOperands]);
        end;
        Pending.Add(Item.Value);
        Continue;
      end;
      ConvertCommand(Pending.ToArray, Item.Code);
      Pending.Clear;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TType2Converter.ConvertCommand(const Numbers: TArray<Double>; const Code: Integer);
begin
  case Code of
    CodeHStem, CodeHStemHM, CodeVStem, CodeVStemHM, CodeHintMask, CodeCntrMask:
      // The stem hints do not change the path
      ClearStack(Numbers, Odd(Length(Numbers)));
    CodeHMoveTo, CodeVMoveTo, CodeRMoveTo:
      ConvertMove(Numbers, Code);
    CodeEndChar:
      ConvertEndChar(Numbers);
    CodeRLineTo, CodeHLineTo, CodeVLineTo:
      ConvertLines(Numbers, Code);
    CodeRRCurveTo, CodeHVCurveTo, CodeVHCurveTo, CodeHHCurveTo, CodeVVCurveTo, CodeRCurveLine, CodeRLineCurve:
      ConvertCurves(Numbers, Code);
    CodeHFlex, CodeFlex, CodeHFlex1, CodeFlex1:
      ConvertFlex(Numbers, Code);
  else
    AddCommand(Numbers, Code);
  end;
end;

procedure TType2Converter.ConvertMove(const Numbers: TArray<Double>; const Code: Integer);
begin
  var MoveLimit := 1;
  if Code = CodeRMoveTo then
  begin
    MoveLimit := 2;
  end;
  const Cleared = ClearStack(Numbers, Length(Numbers) > MoveLimit);
  MarkPath;
  AddCommand(Cleared, Code);
end;

procedure TType2Converter.ConvertEndChar(const Numbers: TArray<Double>);
begin
  const Cleared = ClearStack(Numbers, (Length(Numbers) = 5) or (Length(Numbers) = 1));
  CloseCharString2Path;
  if Length(Cleared) = 4 then
  begin
    // The deprecated seac operator: asb adx ady bchar achar, with asb 0
    AddCommand([0, Cleared[0], Cleared[1], Cleared[2], Cleared[3]], CodeSeac);
  end
  else
  begin
    AddCommand(Cleared, CodeEndChar);
  end;
end;

procedure TType2Converter.ConvertLines(const Numbers: TArray<Double>; const Code: Integer);
begin
  case Code of
    CodeRLineTo:
      AddSplit(Numbers, 0, Length(Numbers), 2, CodeRLineTo);
    CodeHLineTo:
      AddAlternatingLine(Numbers, True);
    CodeVLineTo:
      AddAlternatingLine(Numbers, False);
  end;
end;

procedure TType2Converter.ConvertCurves(const Numbers: TArray<Double>; const Code: Integer);
begin
  case Code of
    CodeRRCurveTo:
      AddSplit(Numbers, 0, Length(Numbers), 6, CodeRRCurveTo);
    CodeHVCurveTo:
      AddAlternatingCurve(Numbers, True);
    CodeVHCurveTo:
      AddAlternatingCurve(Numbers, False);
    CodeHHCurveTo:
      AddCurve(Numbers, True);
    CodeVVCurveTo:
      AddCurve(Numbers, False);
    CodeRCurveLine:
      AddRCurveLine(Numbers);
    CodeRLineCurve:
      AddRLineCurve(Numbers);
  end;
end;

procedure TType2Converter.ConvertFlex(const Numbers: TArray<Double>; const Code: Integer);
begin
  case Code of
    CodeHFlex:
      AddHFlex(Numbers);
    CodeFlex:
      AddFlex(Numbers);
    CodeHFlex1:
      AddHFlex1(Numbers);
    CodeFlex1:
      AddFlex1(Numbers);
  end;
end;

// The first operator that gives a path or hint of the charstring starts the sequence with an hsbw, as a Type 1 charstring
// does. The width that may be among the operands is not needed for the path.
function TType2Converter.ClearStack(const Numbers: TArray<Double>; const HasWidth: Boolean): TArray<Double>;
begin
  Result := Numbers;
  if FConverted.Count > 0 then
  begin
    Exit;
  end;

  if HasWidth then
  begin
    Operand(Numbers, 0);
    Result := Copy(Numbers, 1, Length(Numbers) - 1);
  end;
  AddCommand([0, 0], CodeHSBW);
end;

procedure TType2Converter.MarkPath;
begin
  if FPathCount > 0 then
  begin
    CloseCharString2Path;
  end;
  Inc(FPathCount);
end;

procedure TType2Converter.CloseCharString2Path;
begin
  if FPathCount = 0 then
  begin
    Exit;
  end;
  if FConverted.Last.Code <> CodeClosePath then
  begin
    AddCommand([], CodeClosePath);
  end;
end;

procedure TType2Converter.AddCommand(const Numbers: array of Double; const Code: Integer);
begin
  for var Value in Numbers do
  begin
    var Item := Default(TCharStringItem);
    Item.Value := Value;
    FConverted.Add(Item);
  end;
  var Command := Default(TCharStringItem);
  Command.IsCommand := True;
  Command.Code := Code;
  FConverted.Add(Command);
end;

// The groups of Size operands in Numbers[First .. First + Count - 1]; operands that do not make a whole group are dropped
procedure TType2Converter.AddSplit(const Numbers: TArray<Double>; const First, Count, Size, Code: Integer);
begin
  for var Group := 0 to (Count div Size) - 1 do
  begin
    const Start = First + Group * Size;
    AddCommand(Copy(Numbers, Start, Size), Code);
  end;
end;

procedure TType2Converter.AddAlternatingLine(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
begin
  var Horizontal := IsHorizontal;
  for var Value in Numbers do
  begin
    if Horizontal then
    begin
      AddCommand([Value], CodeHLineTo);
    end
    else
    begin
      AddCommand([Value], CodeVLineTo);
    end;
    Horizontal := not Horizontal;
  end;
end;

procedure TType2Converter.AddAlternatingCurve(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
begin
  var Horizontal := IsHorizontal;
  var Start := 0;
  while Length(Numbers) - Start >= 4 do
  begin
    const IsLast = (Length(Numbers) - Start = 5);
    var Extra: Double := 0;
    if IsLast then
    begin
      Extra := Numbers[Start + 4];
    end;
    if Horizontal then
    begin
      AddCommand([Numbers[Start], 0, Numbers[Start + 1], Numbers[Start + 2], Extra, Numbers[Start + 3]], CodeRRCurveTo);
    end
    else
    begin
      AddCommand([0, Numbers[Start], Numbers[Start + 1], Numbers[Start + 2], Numbers[Start + 3], Extra], CodeRRCurveTo);
    end;
    if IsLast then
    begin
      Inc(Start, 5);
    end
    else
    begin
      Inc(Start, 4);
    end;
    Horizontal := not Horizontal;
  end;
end;

// hhcurveto and vvcurveto: a curve of 4 operands, the first curve of an odd number of operands has one more at the front
procedure TType2Converter.AddCurve(const Numbers: TArray<Double>; const IsHorizontal: Boolean);
begin
  var Start := 0;
  while Length(Numbers) - Start >= 4 do
  begin
    const IsFirst = ((Length(Numbers) - Start) mod 4 = 1);
    var Shift := 0;
    var Lead: Double := 0;
    if IsFirst then
    begin
      Shift := 1;
      Lead := Numbers[Start];
    end;
    if IsHorizontal then
    begin
      AddCommand([Numbers[Start + Shift], Lead, Numbers[Start + Shift + 1], Numbers[Start + Shift + 2],
                  Numbers[Start + Shift + 3], 0], CodeRRCurveTo);
    end
    else
    begin
      AddCommand([Lead, Numbers[Start + Shift], Numbers[Start + Shift + 1], Numbers[Start + Shift + 2], 0,
                  Numbers[Start + Shift + 3]], CodeRRCurveTo);
    end;
    Inc(Start, 4 + Shift);
  end;
end;

procedure TType2Converter.AddHFlex(const Numbers: TArray<Double>);
begin
  if Length(Numbers) < 7 then
  begin
    Exit;
  end;
  AddCommand([Numbers[0], 0, Numbers[1], Numbers[2], Numbers[3], 0], CodeRRCurveTo);
  AddCommand([Numbers[4], 0, Numbers[5], Negated(Numbers[2]), Numbers[6], 0], CodeRRCurveTo);
end;

procedure TType2Converter.AddFlex(const Numbers: TArray<Double>);
begin
  // The operand 11 is the one that PDFBox needs and the 13th (the flex depth) is dropped
  Operand(Numbers, 11);
  AddSplit(Numbers, 0, 12, 6, CodeRRCurveTo);
end;

procedure TType2Converter.AddHFlex1(const Numbers: TArray<Double>);
begin
  if Length(Numbers) < 9 then
  begin
    Exit;
  end;
  AddCommand([Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], 0], CodeRRCurveTo);
  AddCommand([Numbers[5], 0, Numbers[6], Numbers[7], Numbers[8], 0], CodeRRCurveTo);
end;

// The last point of flex1 is on the line that the other points give: it has the larger of the two offsets, and the other
// offset closes the sum to 0
procedure TType2Converter.AddFlex1(const Numbers: TArray<Double>);
begin
  Operand(Numbers, 10);
  var SumX := 0;
  var SumY := 0;
  for var Pair := 0 to 4 do
  begin
    Inc(SumX, TCFFNumber.ToInt(Numbers[Pair * 2]));
    Inc(SumY, TCFFNumber.ToInt(Numbers[Pair * 2 + 1]));
  end;

  AddCommand([Numbers[0], Numbers[1], Numbers[2], Numbers[3], Numbers[4], Numbers[5]], CodeRRCurveTo);
  if Abs(SumX) > Abs(SumY) then
  begin
    AddCommand([Numbers[6], Numbers[7], Numbers[8], Numbers[9], Numbers[10], -SumY], CodeRRCurveTo);
  end
  else
  begin
    AddCommand([Numbers[6], Numbers[7], Numbers[8], Numbers[9], -SumX, Numbers[10]], CodeRRCurveTo);
  end;
end;

procedure TType2Converter.AddRCurveLine(const Numbers: TArray<Double>);
begin
  if Length(Numbers) < 2 then
  begin
    Exit;
  end;
  AddSplit(Numbers, 0, Length(Numbers) - 2, 6, CodeRRCurveTo);
  AddCommand(Copy(Numbers, Length(Numbers) - 2, 2), CodeRLineTo);
end;

procedure TType2Converter.AddRLineCurve(const Numbers: TArray<Double>);
begin
  if Length(Numbers) < 6 then
  begin
    Exit;
  end;
  AddSplit(Numbers, 0, Length(Numbers) - 6, 2, CodeRLineTo);
  AddCommand(Copy(Numbers, Length(Numbers) - 6, 6), CodeRRCurveTo);
end;

{ TCharStringPath }

class procedure TCharStringPath.WarnDamage(const Log: TPdfLog; const Reason: string);
begin
  if Assigned(Log) then
  begin
    Log.Warning(Type2DamageMessage, [Reason]);
  end;
end;

class function TCharStringPath.Type1Path(const CharString: TBytes; const Subrs: TArray<TBytes>;
                                         const Lookup: TFunc<string, TBytes>; const Log: TPdfLog): TPdfPath;
begin
  const Outline = TType1Renderer.Render(CharString, Subrs, Lookup, Log, 0);
  try
    Result := Outline.ToPath;
  finally
    Outline.Free;
  end;
end;

class function TCharStringPath.Type2Path(const CharString: TBytes; const GlobalSubrs, LocalSubrs: TArray<TBytes>;
                                         const Log: TPdfLog): TPdfPath;
begin
  const Reader = TType2Reader.Create(GlobalSubrs, LocalSubrs, 0, 0, Log);
  try
    const Converter = TType2Converter.Create;
    try
      try
        Reader.ReadAll(CharString);
      except
        on Failure: EPdfParseException do
        begin
          WarnDamage(Log, Failure.Message);
        end;
      end;
      try
        Converter.Convert(Reader.Items);
      except
        on Failure: EPdfParseException do
        begin
          WarnDamage(Log, Failure.Message);
        end;
      end;
      const Outline = TType1Renderer.RenderConverted(Converter.Converted, Log);
      try
        Result := Outline.ToPath;
      finally
        Outline.Free;
      end;
    finally
      Converter.Free;
    end;
  finally
    Reader.Free;
  end;
end;

end.
