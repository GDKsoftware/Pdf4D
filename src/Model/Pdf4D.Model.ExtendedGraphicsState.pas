// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDExtendedGraphicsState.java (3.0.8), copyIntoGraphicsState for /Font
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/PDFontSetting.java (3.0.8)
unit Pdf4D.Model.ExtendedGraphicsState;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.Resources;

type
  // A view on an ExtGState dictionary. It owns nothing. Only /Font [font size] reaches the graphics state: the other
  // keys (line style, colour, alpha, blend mode and so on) do not matter for text and are ignored (docs/porting.md).
  TPDExtendedGraphicsState = class
  private
    FDictionary: TCosDictionary;

    procedure ApplyFontSetting(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);
    procedure ApplyFontSize(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);

  public
    constructor Create(const Dictionary: TCosDictionary);

    // Sets font and size of the text state from /Font. Like PDFBox the font is set before the size is read. A font that
    // cannot be made is logged and leaves the state alone; a size that is no number is logged and leaves the size alone.
    // The font comes from the font cache of the document context of Resources.
    procedure CopyIntoGraphicsState(const State: TPDGraphicsState; const Resources: TPDResources);

    property CosObject: TCosDictionary read FDictionary;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Font.Base,
  Pdf4D.Font.Factory;

{ TPDExtendedGraphicsState }

constructor TPDExtendedGraphicsState.Create(const Dictionary: TCosDictionary);
begin
  if not Assigned(Dictionary) then
  begin
    raise EArgumentNilException.Create('Dictionary');
  end;

  inherited Create;
  FDictionary := Dictionary;
end;

procedure TPDExtendedGraphicsState.CopyIntoGraphicsState(const State: TPDGraphicsState; const Resources: TPDResources);
begin
  if (not Assigned(State)) or (not Assigned(Resources)) then
  begin
    raise EArgumentNilException.Create('State and Resources are required');
  end;

  var FontSetting: TCosArray;
  if FDictionary.TryGetCosArray(TCosNames.Font, FontSetting) then
  begin
    ApplyFontSetting(FontSetting, State, Resources);
  end;
end;

procedure TPDExtendedGraphicsState.ApplyFontSetting(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);
begin
  var Font: TPDFont := nil;
  const HasFontEntry = ((FontSetting.Count > 0) and (FontSetting.GetObject(0) is TCosDictionary));
  if HasFontEntry then
  begin
    try
      Font := TPDFontFactory.GetFont(TCosDictionary(FontSetting.GetObject(0)), Resources.Context);
    except
      on Error: Exception do
      begin
        const IsRecoverable = ((Error is EPdfException) or TPdfFailure.IsInputFailure(Error));
        if not IsRecoverable then
        begin
          raise;
        end;
        if Assigned(Resources.Context.Log) then
        begin
          Resources.Context.Log.Error('Could not read the font of an ExtGState: %s', [Error.Message]);
        end;
        Exit;
      end;
    end;
  end;

  State.TextState.Font := Font;
  ApplyFontSize(FontSetting, State, Resources);
end;

procedure TPDExtendedGraphicsState.ApplyFontSize(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);
begin
  const HasSize = ((FontSetting.Count > 1) and (FontSetting.GetObject(1) is TCosNumber));
  if HasSize then
  begin
    State.TextState.FontSize := TCosNumber(FontSetting.GetObject(1)).FloatValue;
  end
  else if Assigned(Resources.Context.Log) then
  begin
    Resources.Context.Log.Error('The font setting of an ExtGState has no font size');
  end;
end;

end.
