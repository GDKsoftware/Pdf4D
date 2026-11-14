// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/text/LegacyPDFStreamEngine.java (3.0.8)
unit Pdf4D.Text.LegacyStreamEngine;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Pdf4D.Common.Matrix,
  Pdf4D.Content.StreamEngine,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Font.Base,
  Pdf4D.Font.CIDFontType2,
  Pdf4D.FontBox.TrueType.Font,
  Pdf4D.Model.DocumentContext,
  Pdf4D.Model.Page,
  Pdf4D.Model.Rectangle,
  Pdf4D.Text.TextPosition;

type
  // The text calculations of PDFBox before its stream engine was corrected, which PDFTextStripper still depends on. They
  // are deliberately not exact: do not use this engine for anything but text extraction.
  //
  // Like PDFBox (which overrides showGlyph without calling the base), the glyph procedures of Type 3 fonts are not run:
  // the text of a Type 3 glyph comes from the font encoding only.
  TLegacyPdfStreamEngine = class(TPdfStreamEngine)
  private
    type
      // A font height in the cache of the document context, which frees it with the document
      TCachedFontHeight = class
      public
        Height: Single;
        constructor Create(const Height: Single);
      end;

  private
    const Thousand: Single = 1000;
    const Hundred: Single = 100;
    const FallbackSpaceWidth: Single = 1.0;
    const AverageSpaceFactor: Single = 0.80;
    const ShortMinValue = -32768;
    const ShortRange = 65536;

  private
    FPageRotation: Integer;
    FPageSize: TPdfRectangle;
    FHasTranslateMatrix: Boolean;
    FTranslateMatrix: TPdfMatrix;

    function GetVerticalDisplacementX(const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector): Single;
    function TryGetTrueTypeFont(const Font: TPDFont; out TrueType: TTrueTypeFont): Boolean;
    function GetFontHeight(const Font: TPDFont): Single;
    function GetSpaceWidthText(const Font: TPDFont): Single;
    function TryGetUnicode(const Font: TPDFont; const Code: Integer; out Unicode: string): Boolean;

  protected
    procedure PrepareEngineForPage(const Page: TPDPage); override;
    // Computes the height of the font. Override this to use other calculations.
    function ComputeFontHeight(const Font: TPDFont): Single; virtual;
    // Called with every text position. The callee becomes the owner; this version frees it.
    procedure ProcessTextPosition(const Text: TTextPosition); virtual;

  public
    constructor Create;
    destructor Destroy; override;

    procedure ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector); override;
  end;

implementation

uses
  System.Math,
  System.Types,
  Pdf4D.Common.Defines,
  Pdf4D.Content.Operators.DrawObject,
  Pdf4D.Content.Operators.State,
  Pdf4D.Content.Operators.Text,
  Pdf4D.Font.Descriptor,
  Pdf4D.Font.GlyphList,
  Pdf4D.Font.Simple,
  Pdf4D.Font.TrueType,
  Pdf4D.Font.Type0,
  Pdf4D.Font.Type3,
  Pdf4D.FontBox.BoundingBox;

{ TLegacyPdfStreamEngine.TCachedFontHeight }

constructor TLegacyPdfStreamEngine.TCachedFontHeight.Create(const Height: Single);
begin
  inherited Create;
  Self.Height := Height;
end;

{ TLegacyPdfStreamEngine }

constructor TLegacyPdfStreamEngine.Create;
begin
  inherited Create;
  TTextOperators.Register(Self);
  TDrawObjectOperators.Register(Self);
  TStateOperators.Register(Self);
end;

destructor TLegacyPdfStreamEngine.Destroy;
begin
  inherited;
end;

// Runs inside the floating point guard of ProcessPage
procedure TLegacyPdfStreamEngine.PrepareEngineForPage(const Page: TPDPage);
begin
  FPageRotation := Page.Rotation;
  FPageSize := Page.CropBox;
  FHasTranslateMatrix := not (TJavaFloat.IsSame(FPageSize.LowerLeftX, 0) and TJavaFloat.IsSame(FPageSize.LowerLeftY, 0));
  if FHasTranslateMatrix then
  begin
    // The translation for a crop box that does not start in the origin
    FTranslateMatrix := TPdfMatrix.GetTranslateInstance(-FPageSize.LowerLeftX, -FPageSize.LowerLeftY);
  end;
end;

function TLegacyPdfStreamEngine.TryGetTrueTypeFont(const Font: TPDFont; out TrueType: TTrueTypeFont): Boolean;
begin
  TrueType := nil;
  if Font is TPDTrueTypeFont then
  begin
    TrueType := TPDTrueTypeFont(Font).GetTrueTypeFont;
  end
  else if Font is TPDType0Font then
  begin
    const CidFont = TPDType0Font(Font).DescendantFont;
    if CidFont is TPDCIDFontType2 then
    begin
      TrueType := TPDCIDFontType2(CidFont).GetTrueTypeFont;
    end;
  end;
  Result := Assigned(TrueType);
end;

function TLegacyPdfStreamEngine.GetVerticalDisplacementX(const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector): Single;
begin
  // The sorting is based on the width of the character. The displacement of a vertical character gives no suitable value for
  // it, so it is calculated here.
  Result := Font.GetWidth(Code) / Thousand;

  // There may be an additional scaling factor for TrueType fonts
  var TrueType: TTrueTypeFont;
  if TryGetTrueTypeFont(Font, TrueType) and (TrueType.UnitsPerEm <> 1000) then
  begin
    Result := Result * (Thousand / TrueType.UnitsPerEm);
  end;
end;

function TLegacyPdfStreamEngine.GetFontHeight(const Font: TPDFont): Single;
begin
  // The cache belongs to the document, so a font of another document can never find a height of this one
  const Context = CurrentPage.Context;
  var Cached: TObject;
  if Context.TryGetCachedObject(TPDCacheScope.FontHeight, Font, Cached) then
  begin
    Exit(TCachedFontHeight(Cached).Height);
  end;

  Result := ComputeFontHeight(Font);
  Context.AddCachedObject(TPDCacheScope.FontHeight, Font, TCachedFontHeight.Create(Result));
end;

function TLegacyPdfStreamEngine.GetSpaceWidthText(const Font: TPDFont): Single;
begin
  // The glyph space is 1/1000 of the text space, except in a Type 3 font
  var GlyphSpaceToTextSpace: Single := 1 / Thousand;
  if Font is TPDType3Font then
  begin
    GlyphSpaceToTextSpace := Font.GetFontMatrix.ScaleX;
  end;

  Result := 0;
  try
    // PDFBOX-614: see what the space displacement should be without breaking on a font that cannot tell
    Result := Font.GetSpaceWidth * GlyphSpaceToTextSpace;
  except
    on Failure: EOutOfMemory do
    begin
      // The operator catch of the engine ends the page
      raise;
    end;
    on Failure: Exception do
    begin
      if TPdfFailure.IsFatal(Failure) then
      begin
        raise;
      end;
      LogWarning('The width of the space could not be read: %s', [Failure.Message]);
    end;
  end;

  if TJavaFloat.IsSame(Result, 0) then
  begin
    Result := Font.GetAverageFontWidth * GlyphSpaceToTextSpace;
    // The average width appears to be higher than necessary
    Result := Result * AverageSpaceFactor;
  end;
  if TJavaFloat.IsSame(Result, 0) then
  begin
    // No font to go by: a generic value
    Result := FallbackSpaceWidth;
  end;
end;

function TLegacyPdfStreamEngine.TryGetUnicode(const Font: TPDFont; const Code: Integer; out Unicode: string): Boolean;
begin
  // The additional glyph list is used for the Unicode mapping
  if Font.TryToUnicode(Code, TGlyphList.TextExtraction, Unicode) then
  begin
    Exit(True);
  end;

  // Without a Unicode mapping Acrobat coerces the character code into Unicode, and so do we. A subclass of the stream engine
  // does not necessarily want that, which is why it is left until here.
  if Font is TPDSimpleFont then
  begin
    Unicode := Char(Code);
    Exit(True);
  end;

  // Acrobat does not coerce the codes of a composite font, it skips them (the TestTextStripper file allah2.pdf)
  Result := False;
end;

procedure TLegacyPdfStreamEngine.ShowGlyph(const TextRenderingMatrix: TPdfMatrix; const Font: TPDFont; const Code: Integer; const Displacement: TPdfVector);
begin
  // The legacy calculations that used to be in the stream engine. They are deliberately incorrect.
  const State = GraphicsState;
  const Ctm = State.CurrentTransformationMatrix;
  const FontSize = State.TextState.FontSize;
  const HorizontalScaling = State.TextState.HorizontalScaling / Hundred;
  var TextMatrix: TPdfMatrix;
  if not State.TryGetTextMatrix(TextMatrix) then
  begin
    Exit;
  end;

  var DisplacementX := Displacement.X;
  if Font.IsVertical then
  begin
    DisplacementX := GetVerticalDisplacementX(Font, Code, Displacement);
  end;

  // The combined displacement, calculated without the character spacing and the word spacing: legacy code of the stripper
  const Tx = DisplacementX * FontSize * HorizontalScaling;
  const Ty = Displacement.Y * FontSize;

  // The text rendering matrix of the next glyph, text space to device space
  const NextTextRenderingMatrix = TPdfMatrix.GetTranslateInstance(Tx, Ty).Multiply(TextMatrix).Multiply(Ctm);
  var NextX := NextTextRenderingMatrix.TranslateX;
  var NextY := NextTextRenderingMatrix.TranslateY;

  const DxDisplay = NextX - TextRenderingMatrix.TranslateX;
  const DyDisplay = GetFontHeight(Font) * TextRenderingMatrix.ScalingFactorY;

  // The space width has to be transformed into display units
  const SpaceWidthDisplay = GetSpaceWidthText(Font) * TextRenderingMatrix.ScalingFactorX;

  var Unicode: string;
  if not TryGetUnicode(Font, Code, Unicode) then
  begin
    Exit;
  end;

  // Adjust for the crop box if needed
  var TranslatedTextRenderingMatrix := TextRenderingMatrix;
  if FHasTranslateMatrix then
  begin
    TranslatedTextRenderingMatrix := TPdfMatrix.Concatenate(FTranslateMatrix, TextRenderingMatrix);
    NextX := NextX - FPageSize.LowerLeftX;
    NextY := NextY - FPageSize.LowerLeftY;
  end;

  ProcessTextPosition(TTextPosition.Create(FPageRotation, FPageSize.Width, FPageSize.Height, TranslatedTextRenderingMatrix, NextX, NextY,
                                           Abs(DyDisplay), DxDisplay, Abs(SpaceWidthDisplay), Unicode, [Code], Font, FontSize,
                                           TJavaFloat.ToInt(FontSize * TextMatrix.ScalingFactorX)));
end;

function TLegacyPdfStreamEngine.ComputeFontHeight(const Font: TPDFont): Single;
begin
  var BoundingBox := Font.GetBoundingBox;
  if BoundingBox.LowerLeftY < ShortMinValue then
  begin
    // PDFBOX-2158 and PDFBOX-3130: files by Salmat eSolutions and the ClibPDF library
    BoundingBox.LowerLeftY := -(BoundingBox.LowerLeftY + ShortRange);
  end;
  // Half of the bounding box is used as the height; PDFBox does not know why either
  var GlyphHeight := BoundingBox.Height / 2;

  // Sometimes the bounding box has very high values, but the cap height is fine
  var Descriptor: TPDFontDescriptor;
  if Font.TryGetFontDescriptor(Descriptor) then
  begin
    const CapHeight = Descriptor.CapHeight;
    if (not TJavaFloat.IsSame(CapHeight, 0)) and ((CapHeight < GlyphHeight) or TJavaFloat.IsSame(GlyphHeight, 0)) then
    begin
      GlyphHeight := CapHeight;
    end;
    // PDFBOX-3464, PDFBOX-4480, PDFBOX-4553: sometimes even the cap height has a very high value, but ascent and descent are fine
    const Ascent = Descriptor.Ascent;
    const Descent = Descriptor.Descent;
    if (CapHeight > Ascent) and (Ascent > 0) and (Descent < 0) and (((Ascent - Descent) / 2 < GlyphHeight) or TJavaFloat.IsSame(GlyphHeight, 0)) then
    begin
      GlyphHeight := (Ascent - Descent) / 2;
    end;
  end;

  // From glyph space to text space
  if Font is TPDType3Font then
  begin
    Result := Font.GetFontMatrix.TransformPoint(0, GlyphHeight).Y;
  end
  else
  begin
    Result := GlyphHeight / Thousand;
  end;
end;

procedure TLegacyPdfStreamEngine.ProcessTextPosition(const Text: TTextPosition);
begin
  // The subclasses provide the specific behaviour; they own the position
  Text.Free;
end;

end.
