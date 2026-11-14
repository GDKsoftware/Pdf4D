// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType3Font.java (3.0.8)
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/font/PDType3CharProc.java (3.0.8), without the content stream interface
unit Pdf4D.Font.Type3;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Encoding,
  Pdf4D.Font.Simple,
  Pdf4D.FontBox.BoundingBox,
  Pdf4D.FontBox.FontBoxFont,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Rectangle,
  Pdf4D.Parser.ContentStream;

type
  TPDType3Font = class;

  // The glyph procedure of one glyph of a Type 3 font: a stand-alone content stream. Text extraction only needs the
  // operator at its start (d0 or d1), so the procedure is never executed here. Only the start of the decoded stream is read.
  TPDType3CharProc = class
  private
    const MaxPrefixBytes = 65536;
    const GlyphBoundsOperandCount = 6;
    const GlyphBoundsOperatorName = 'd1';
    const WidthOperatorName = 'd0';

    type
      // The operator at the start of a glyph procedure with its first operands
      TFirstOperator = record
        OperatorName: string;
        OperandCount: Integer;
        Numbers: array[0..GlyphBoundsOperandCount - 1] of Single;
        IsNumber: array[0..GlyphBoundsOperandCount - 1] of Boolean;
      end;

  private
    FFont: TPDType3Font;
    FStream: TCosStream;

    function TryReadPrefix(out Prefix: TBytes): Boolean;
    function TryGetFirstOperator(out FirstOperator: TFirstOperator): Boolean;
    function TryReadFirstOperator(const Prefix: TBytes; out FirstOperator: TFirstOperator): Boolean;
    function TryReadOperands(const Parser: TPdfStreamParser; const Operands: TObjectList<TObject>; out FirstOperator: TFirstOperator): Boolean;
    class procedure CopyNumbers(const Operands: TObjectList<TObject>; var FirstOperator: TFirstOperator); static;
    procedure WarnAboutOwnResources;

  public
    // Does not own Font or Stream; both have to outlive the procedure
    constructor Create(const Font: TPDType3Font; const Stream: TCosStream);

    // False when the stream is empty: PDFBox gives width 0 for it
    function HasData: Boolean;
    // The first argument of d0 or d1, when the first operator of the stream is one of them with a number as first argument.
    // False for an empty stream, an unreadable one, another first operator and a first argument that is no number (PDFBox
    // throws an IOException for these).
    function TryGetWidth(out Width: Single): Boolean;
    // The bounding box of d1; False when the first operator is not d1 with six numbers
    function TryGetGlyphBBox(out Box: TPdfRectangle): Boolean;
    // The resources dictionary of the stream itself (which PDFBox warns about), else the resources of the font. False when
    // there is none.
    function TryGetResources(out Resources: TCosDictionary): Boolean;

    property Font: TPDType3Font read FFont;
    property Stream: TCosStream read FStream;
  end;

  // A Type 3 font: the glyphs are content streams. Widths and the font matrix come from the font dictionary, the width of a
  // glyph without /Widths from the d0 or d1 operator of its procedure. The font keeps what Form XObject-like processing of a
  // glyph procedure needs later (the resources and the procedures) as dictionaries of the document.
  TPDType3Font = class(TPDSimpleFont)
  private
    const MaxGlyphBoundsScanned = 4096;
    const MaxCachedWidths = 65536;

  private
    FHasFontMatrix: Boolean;
    FFontMatrix: TPdfMatrix;
    FHasBoundingBox: Boolean;
    FBoundingBox: TBoundingBox;
    FCharProcWidths: TDictionary<Integer, Single>;
    FIsDisplacementWarningGiven: Boolean;

    function TryReadFontMatrix(out Matrix: TPdfMatrix): Boolean;
    function ReadWidthFromCharProc(const Code: Integer): Single;
    function GenerateBoundingBox: TBoundingBox;
    procedure ExtendByGlyphBounds(var Box: TPdfRectangle);
    procedure ExtendByCharProc(const Stream: TCosStream; var Box: TPdfRectangle);
    procedure WarnAboutDisplacement;

  protected
    // PDType3Font.readEncoding: /Encoding is a name or a dictionary, the glyph list is the Adobe glyph list
    procedure ReadEncoding; override;
    // Type 3 fonts do not have a built-in encoding
    function ReadEncodingFromFont: TPdfEncoding; override;
    // The /Name entry, not /BaseFont
    function GetName: string; override;

  public
    // Does not own Dictionary or Context
    constructor Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
    destructor Destroy; override;

    // The /Widths entry for a code between /FirstChar and /LastChar (0 beyond the array), else the /MissingWidth of the
    // descriptor when there is one, else the width of the glyph procedure. In glyph space: the font matrix scales it.
    function GetWidth(const Code: Integer): Single; override;
    // The width of the d0 or d1 operator of the glyph procedure; 0 when the glyph has no procedure or it has no data. A
    // procedure whose width cannot be read gives 0 and a warning, where PDFBox raises an IOException.
    function GetWidthFromFont(const Code: Integer): Single; override;
    // The width through the font matrix, not the 1/1000 of other fonts. A result that is not finite (a huge matrix or width)
    // gives a displacement of 0 and a warning, where PDFBox continues with an infinity.
    function GetDisplacement(const Code: Integer): TPdfVector; override;
    // /FontMatrix when it holds six numbers, else the default 0.001 0 0 0.001 0 0
    function GetFontMatrix: TPdfMatrix; override;
    function GetBoundingBox: TBoundingBox; override;
    // An average height from the descriptor: half the bounding box, else the cap height, ascent or x-height. 0 without one.
    function GetHeight(const Code: Integer): Single;
    // Type 3 fonts are embedded by design
    function IsEmbedded: Boolean; override;
    // There is no font file to load
    function IsDamaged: Boolean; override;
    function IsStandard14: Boolean; override;
    function IsSymbolic: Boolean; override;
    // Raises EPdfUnsupportedFeatureException: Type 3 fonts do not use FontBox fonts
    function GetFontBoxFont: TFontBoxFont; override;

    // Whether /CharProcs has a stream for the glyph name
    function HasGlyph(const GlyphName: string): Boolean;
    // /CharProcs: the glyph names with their procedures. The dictionary belongs to the document.
    function TryGetCharProcs(out CharProcs: TCosDictionary): Boolean;
    // The procedure of the glyph that the encoding names for Code. False without an encoding, without /CharProcs and for a
    // glyph that has no stream there. The stream belongs to the document.
    function TryGetCharProc(const Code: Integer; out CharProc: TCosStream): Boolean;
    // /Resources of the font, for the glyph procedures that have none of their own. The dictionary belongs to the document.
    function TryGetResources(out Resources: TCosDictionary): Boolean;
    // /FontBBox as a rectangle; False when the entry is missing
    function TryGetFontBBox(out Box: TPdfRectangle): Boolean;
  end;

implementation

uses
  System.Classes,
  System.Math,
  Pdf4D.Common.Defines,
  Pdf4D.Common.Log,
  Pdf4D.Content.Operator,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Font.Descriptor;

const
  FontMatrixItemCount = 6;

{ TPDType3CharProc }

constructor TPDType3CharProc.Create(const Font: TPDType3Font; const Stream: TCosStream);
begin
  inherited Create;
  if (not Assigned(Font)) or (not Assigned(Stream)) then
  begin
    raise EArgumentNilException.Create('A glyph procedure needs a font and a stream');
  end;

  FFont := Font;
  FStream := Stream;
end;

function TPDType3CharProc.HasData: Boolean;
begin
  Result := (Length(FStream.ReadRawPrefix(1)) > 0);
end;

function TPDType3CharProc.TryReadPrefix(out Prefix: TBytes): Boolean;
begin
  Prefix := nil;
  Result := False;
  try
    const Decoded = FStream.CreateDecodedStream;
    try
      const Count = Min(Decoded.Size, Int64(MaxPrefixBytes));
      SetLength(Prefix, Count);
      Decoded.Position := 0;
      if Count > 0 then
      begin
        Decoded.ReadBuffer(Prefix, Integer(Count));
      end;
    finally
      Decoded.Free;
    end;
    Result := True;
  except
    on Failure: Exception do
    begin
      const IsRecoverable = ((Failure is EPdfException) or TPdfFailure.IsInputFailure(Failure));
      if not IsRecoverable then
      begin
        raise;
      end;
      Prefix := nil;
    end;
  end;
end;

function TPDType3CharProc.TryReadFirstOperator(const Prefix: TBytes; out FirstOperator: TFirstOperator): Boolean;
begin
  const Context = FFont.Context;
  var Options := TPdfLoadOptions.Default;
  var Log: TPdfLog := nil;
  if Assigned(Context) then
  begin
    Options := Context.Options;
    Log := Context.Log;
  end;

  const Operands = TObjectList<TObject>.Create(True);
  try
    const Parser = TPdfStreamParser.Create(Prefix, Options, Log);
    try
      Result := TryReadOperands(Parser, Operands, FirstOperator);
    finally
      // The operands may hold proxies of the parser, so they go before it
      Operands.Clear;
      Parser.Free;
    end;
  finally
    Operands.Free;
  end;
end;

function TPDType3CharProc.TryReadOperands(const Parser: TPdfStreamParser; const Operands: TObjectList<TObject>;
                                          out FirstOperator: TFirstOperator): Boolean;
begin
  FirstOperator := Default(TFirstOperator);
  Result := False;
  try
    var Token := Parser.ParseNextToken;
    while Assigned(Token) do
    begin
      if Token is TContentOperator then
      begin
        FirstOperator.OperatorName := TContentOperator(Token).Name;
        Token.Free;
        CopyNumbers(Operands, FirstOperator);
        Exit(True);
      end;
      Operands.Add(Token);
      Token := Parser.ParseNextToken;
    end;
  except
    on EPdfException do
    begin
      // A stream that does not parse has no first operator
      Exit(False);
    end;
  end;
end;

class procedure TPDType3CharProc.CopyNumbers(const Operands: TObjectList<TObject>; var FirstOperator: TFirstOperator);
begin
  FirstOperator.OperandCount := Operands.Count;
  for var Index := 0 to Min(Operands.Count, GlyphBoundsOperandCount) - 1 do
  begin
    const IsNumber = (Operands[Index] is TCosNumber);
    FirstOperator.IsNumber[Index] := IsNumber;
    if IsNumber then
    begin
      FirstOperator.Numbers[Index] := TCosNumber(Operands[Index]).FloatValue;
    end;
  end;
end;

function TPDType3CharProc.TryGetFirstOperator(out FirstOperator: TFirstOperator): Boolean;
begin
  var Prefix: TBytes;
  Result := (TryReadPrefix(Prefix) and TryReadFirstOperator(Prefix, FirstOperator));
end;

function TPDType3CharProc.TryGetWidth(out Width: Single): Boolean;
begin
  Width := 0;
  var FirstOperator: TFirstOperator;
  const IsWidthOperator = (TryGetFirstOperator(FirstOperator) and
                           ((FirstOperator.OperatorName = WidthOperatorName) or (FirstOperator.OperatorName = GlyphBoundsOperatorName)));
  Result := (IsWidthOperator and (FirstOperator.OperandCount > 0) and FirstOperator.IsNumber[0]);
  if Result then
  begin
    Width := FirstOperator.Numbers[0];
  end;
end;

function TPDType3CharProc.TryGetGlyphBBox(out Box: TPdfRectangle): Boolean;
begin
  Box := Default(TPdfRectangle);
  Result := False;
  var FirstOperator: TFirstOperator;
  const IsGlyphBounds = (TryGetFirstOperator(FirstOperator) and (FirstOperator.OperatorName = GlyphBoundsOperatorName) and
                         (FirstOperator.OperandCount = GlyphBoundsOperandCount));
  if not IsGlyphBounds then
  begin
    Exit;
  end;

  for var Index := 0 to GlyphBoundsOperandCount - 1 do
  begin
    if not FirstOperator.IsNumber[Index] then
    begin
      Exit;
    end;
  end;

  // new PDRectangle(x, y, width, height), with the width and height as the differences of the corners
  const X = FirstOperator.Numbers[2];
  const Y = FirstOperator.Numbers[3];
  const BoxWidth = FirstOperator.Numbers[4] - X;
  const BoxHeight = FirstOperator.Numbers[5] - Y;
  Box.LowerLeftX := X;
  Box.LowerLeftY := Y;
  Box.UpperRightX := X + BoxWidth;
  Box.UpperRightY := Y + BoxHeight;
  Result := True;
end;
procedure TPDType3CharProc.WarnAboutOwnResources;
begin
  const Context = FFont.Context;
  if Assigned(Context) and Assigned(Context.Log) then
  begin
    Context.Log.Warning('Using resources dictionary found in charproc entry; this should have been in the font or in the page dictionary', []);
  end;
end;

function TPDType3CharProc.TryGetResources(out Resources: TCosDictionary): Boolean;
begin
  if FStream.ContainsKey(TCosNames.Resources) then
  begin
    // PDFBOX-5294: the resources should have been in the font or in the page dictionary
    Result := FStream.TryGetCosDictionary(TCosNames.Resources, Resources);
    if Result then
    begin
      WarnAboutOwnResources;
      Exit;
    end;
  end;
  Result := FFont.TryGetResources(Resources);
end;

{ TPDType3Font }

constructor TPDType3Font.Create(const Dictionary: TCosDictionary; const Context: TPDDocumentContext);
begin
  inherited Create(Dictionary, Context);
  FCharProcWidths := TDictionary<Integer, Single>.Create;
  ReadEncoding;
end;

destructor TPDType3Font.Destroy;
begin
  FCharProcWidths.Free;
  inherited;
end;

function TPDType3Font.GetName: string;
begin
  Result := CosObject.GetNameAsString(TCosNames.Name, '');
end;

procedure TPDType3Font.ReadEncoding;
begin
  var EncodingEntry: TCosBase;
  if CosObject.TryGetDictionaryObject(TCosNames.Encoding, EncodingEntry) then
  begin
    if EncodingEntry is TCosName then
    begin
      const EncodingName = TCosName(EncodingEntry).Name;
      var Encoding: TPdfEncoding;
      if TPdfEncoding.TryGetInstance(EncodingName, Encoding) then
      begin
        AssignEncoding(Encoding);
      end
      else
      begin
        LogWarning('Unknown encoding: %s', [EncodingName]);
      end;
    end
    else if EncodingEntry is TCosDictionary then
    begin
      AssignEncoding(AdoptEncoding(TDictionaryEncoding.CreateForType3(TCosDictionary(EncodingEntry))));
    end;
  end;
  AssignAdobeGlyphList;
end;

function TPDType3Font.ReadEncodingFromFont: TPdfEncoding;
begin
  raise EPdfUnsupportedFeatureException.Create('Reading the built-in encoding is not supported for Type 3 fonts');
end;

function TPDType3Font.GetFontBoxFont: TFontBoxFont;
begin
  raise EPdfUnsupportedFeatureException.Create('Type 3 fonts do not use FontBox fonts');
end;

function TPDType3Font.IsSymbolic: Boolean;
begin
  Result := False;
end;

function TPDType3Font.IsStandard14: Boolean;
begin
  Result := False;
end;

function TPDType3Font.IsEmbedded: Boolean;
begin
  Result := True;
end;

function TPDType3Font.IsDamaged: Boolean;
begin
  Result := False;
end;

function TPDType3Font.HasGlyph(const GlyphName: string): Boolean;
begin
  var CharProcs: TCosDictionary;
  var CharProc: TCosStream;
  Result := (TryGetCharProcs(CharProcs) and CharProcs.TryGetCosStream(GlyphName, CharProc));
end;

function TPDType3Font.TryGetCharProcs(out CharProcs: TCosDictionary): Boolean;
begin
  Result := CosObject.TryGetCosDictionary(TCosNames.CharProcs, CharProcs);
end;

function TPDType3Font.TryGetCharProc(const Code: Integer; out CharProc: TCosStream): Boolean;
begin
  CharProc := nil;
  var Encoding: TPdfEncoding;
  var CharProcs: TCosDictionary;
  if not (TryGetEncoding(Encoding) and TryGetCharProcs(CharProcs)) then
  begin
    Exit(False);
  end;

  Result := CharProcs.TryGetCosStream(Encoding.GetName(Code), CharProc);
end;

function TPDType3Font.TryGetResources(out Resources: TCosDictionary): Boolean;
begin
  Result := CosObject.TryGetCosDictionary(TCosNames.Resources, Resources);
end;

function TPDType3Font.TryGetFontBBox(out Box: TPdfRectangle): Boolean;
begin
  Box := Default(TPdfRectangle);
  var BoxArray: TCosArray;
  Result := CosObject.TryGetCosArray(TCosNames.FontBBox, BoxArray);
  if Result then
  begin
    Box := TPdfRectangle.FromCosArray(BoxArray);
  end;
end;

function TPDType3Font.GetWidth(const Code: Integer): Single;
begin
  const FirstChar = CosObject.GetInt(TCosNames.FirstChar, -1);
  const LastChar = CosObject.GetInt(TCosNames.LastChar, -1);
  const Widths = GetWidths;
  const IsInWidthsRange = ((Length(Widths) > 0) and (Code >= FirstChar) and (Code <= LastChar));
  if IsInWidthsRange then
  begin
    const Index = Int64(Code) - FirstChar;
    if Index >= Length(Widths) then
    begin
      Exit(0);
    end;
    Exit(Widths[Integer(Index)]);
  end;

  var Descriptor: TPDFontDescriptor;
  if TryGetFontDescriptor(Descriptor) then
  begin
    Exit(Descriptor.MissingWidth);
  end;
  Result := GetWidthFromFont(Code);
end;

function TPDType3Font.ReadWidthFromCharProc(const Code: Integer): Single;
begin
  Result := 0;
  var Stream: TCosStream;
  if not TryGetCharProc(Code, Stream) then
  begin
    Exit;
  end;

  const CharProc = TPDType3CharProc.Create(Self, Stream);
  try
    if not CharProc.HasData then
    begin
      Exit;
    end;
    if not CharProc.TryGetWidth(Result) then
    begin
      Result := 0;
      LogWarning('Could not read the width of the glyph procedure of code %d in font %s', [Code, Name]);
    end;
  finally
    CharProc.Free;
  end;
end;

function TPDType3Font.GetWidthFromFont(const Code: Integer): Single;
begin
  // Every read of a glyph procedure decodes its stream, so a width is only read once for a code
  if FCharProcWidths.TryGetValue(Code, Result) then
  begin
    Exit;
  end;

  Result := ReadWidthFromCharProc(Code);
  if FCharProcWidths.Count < MaxCachedWidths then
  begin
    FCharProcWidths.Add(Code, Result);
  end;
end;

procedure TPDType3Font.WarnAboutDisplacement;
begin
  if not FIsDisplacementWarningGiven then
  begin
    FIsDisplacementWarningGiven := True;
    LogWarning('The font matrix of Type 3 font %s gives a displacement that is out of range', [Name]);
  end;
end;

function TPDType3Font.GetDisplacement(const Code: Integer): TPdfVector;
begin
  const Matrix = GetFontMatrix;
  const Width = GetWidth(Code);
  try
    Result := Matrix.Transform(TPdfVector.Create(Width, 0));
    const IsFinite = (not (IsNan(Result.X) or IsInfinite(Result.X) or IsNan(Result.Y) or IsInfinite(Result.Y)));
    if IsFinite then
    begin
      Exit;
    end;
  except
    on EMathError do
    begin
      // The same as a result that is not finite
    end;
  end;

  WarnAboutDisplacement;
  Result := TPdfVector.Create(0, 0);
end;

function TPDType3Font.TryReadFontMatrix(out Matrix: TPdfMatrix): Boolean;
begin
  Matrix := Default(TPdfMatrix);
  var Values: TCosArray;
  if (not CosObject.TryGetCosArray(TCosNames.FontMatrix, Values)) or (Values.Count <> FontMatrixItemCount) then
  begin
    Exit(False);
  end;

  for var Index := 0 to FontMatrixItemCount - 1 do
  begin
    if not (Values.GetObject(Index) is TCosNumber) then
    begin
      Exit(False);
    end;
  end;
  Matrix := TPdfMatrix.FromCosArray(Values);
  Result := True;
end;

function TPDType3Font.GetFontMatrix: TPdfMatrix;
begin
  if not FHasFontMatrix then
  begin
    if not TryReadFontMatrix(FFontMatrix) then
    begin
      FFontMatrix := inherited GetFontMatrix;
    end;
    FHasFontMatrix := True;
  end;
  Result := FFontMatrix;
end;

procedure TPDType3Font.ExtendByCharProc(const Stream: TCosStream; var Box: TPdfRectangle);
begin
  const CharProc = TPDType3CharProc.Create(Self, Stream);
  try
    var GlyphBox: TPdfRectangle;
    if not CharProc.TryGetGlyphBBox(GlyphBox) then
    begin
      Exit;
    end;

    Box.LowerLeftX := Min(Box.LowerLeftX, GlyphBox.LowerLeftX);
    Box.LowerLeftY := Min(Box.LowerLeftY, GlyphBox.LowerLeftY);
    Box.UpperRightX := Max(Box.UpperRightX, GlyphBox.UpperRightX);
    Box.UpperRightY := Max(Box.UpperRightY, GlyphBox.UpperRightY);
  finally
    CharProc.Free;
  end;
end;

// Plan B of PDFBox: the largest bounding box of the glyphs. A font can name any number of glyph procedures, so only the first
// MaxGlyphBoundsScanned are looked at.
procedure TPDType3Font.ExtendByGlyphBounds(var Box: TPdfRectangle);
begin
  var CharProcs: TCosDictionary;
  if not TryGetCharProcs(CharProcs) then
  begin
    Exit;
  end;

  var Scanned := 0;
  for var GlyphName in CharProcs.Keys do
  begin
    var Stream: TCosStream;
    if not CharProcs.TryGetCosStream(GlyphName, Stream) then
    begin
      Continue;
    end;

    Inc(Scanned);
    if Scanned > MaxGlyphBoundsScanned then
    begin
      LogWarning('Type 3 font %s has more than %d glyph procedures; the others are left out of its bounding box', [Name, MaxGlyphBoundsScanned]);
      Break;
    end;
    ExtendByCharProc(Stream, Box);
  end;
end;

function TPDType3Font.GenerateBoundingBox: TBoundingBox;
begin
  var Box: TPdfRectangle;
  if not TryGetFontBBox(Box) then
  begin
    LogWarning('FontBBox missing, returning empty rectangle', []);
    Exit(Default(TBoundingBox));
  end;

  if not IsNonZeroBoundingBox(Box) then
  begin
    ExtendByGlyphBounds(Box);
  end;
  Result := TBoundingBox.Create(Box.LowerLeftX, Box.LowerLeftY, Box.UpperRightX, Box.UpperRightY);
end;

function TPDType3Font.GetBoundingBox: TBoundingBox;
begin
  if not FHasBoundingBox then
  begin
    FBoundingBox := GenerateBoundingBox;
    FHasBoundingBox := True;
  end;
  Result := FBoundingBox;
end;

function TPDType3Font.GetHeight(const Code: Integer): Single;
begin
  Result := 0;
  var Descriptor: TPDFontDescriptor;
  if not TryGetFontDescriptor(Descriptor) then
  begin
    Exit;
  end;

  // The values are all more or less accurate, at least all are average values
  var Box: TPdfRectangle;
  if Descriptor.TryGetFontBoundingBox(Box) then
  begin
    Result := Box.Height / 2;
  end;
  if Result = 0 then
  begin
    Result := Descriptor.CapHeight;
  end;
  if Result = 0 then
  begin
    Result := Descriptor.Ascent;
  end;
  if Result = 0 then
  begin
    Result := Descriptor.XHeight;
    if Result > 0 then
    begin
      Result := Result - Descriptor.Descent;
    end;
  end;
end;

end.
