// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/state/PDExtendedGraphicsState.java (3.0.8), copyIntoGraphicsState for /Font
// and the getters of the other keys
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/blend/BlendMode.java (3.0.8), getInstance as far as the name goes
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/PDFontSetting.java (3.0.8)
unit Pdf4D.Model.ExtendedGraphicsState;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Content.GraphicsState,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Cos.PdfArray,
  Pdf4D.Model.Resources;

type
  // A view on an ExtGState dictionary. It owns nothing. CopyIntoGraphicsState only copies /Font [font size], which is all that
  // text extraction needs. The renderer reads the other keys (line style, alpha, blend mode and so on) through the getters
  // and applies them to its own graphics state.
  TPDExtendedGraphicsState = class
  private
    FDictionary: TCosDictionary;

    procedure ApplyFontSetting(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);
    procedure ApplyFontSize(const FontSetting: TCosArray; const State: TPDGraphicsState; const Resources: TPDResources);
    function TryGetFloatItem(const Key: string; out Value: Single): Boolean;
    function GetTransferItem(const Key: string): TCosBase;
    class function IsBlendModeName(const Name: string): Boolean; static;

  public
    constructor Create(const Dictionary: TCosDictionary);

    // Sets font and size of the text state from /Font. Like PDFBox the font is set before the size is read. A font that
    // cannot be made is logged and leaves the state alone; a size that is no number is logged and leaves the size alone.
    // The font comes from the font cache of the document context of Resources.
    procedure CopyIntoGraphicsState(const State: TPDGraphicsState; const Resources: TPDResources);

    // The line width, miter limit, flatness and alpha constants are False when the entry is missing or no number: PDFBox gives null
    function TryGetLineWidth(out Width: Single): Boolean;
    // -1 when the entry is missing or no number, like COSDictionary.getInt
    function GetLineCapStyle: Integer;
    function GetLineJoinStyle: Integer;
    function TryGetMiterLimit(out Limit: Single): Boolean;
    // /D [[dash array] phase]: False unless it is an array of two with an array and a number
    function TryGetLineDashPattern(out DashArray: TCosArray; out Phase: Integer): Boolean;
    // False when /RI is missing or no name. The name is returned as written; mapping an unknown name is up to the caller.
    function TryGetRenderingIntent(out Intent: string): Boolean;
    function TryGetFlatnessTolerance(out Flatness: Single): Boolean;
    function GetAutomaticStrokeAdjustment: Boolean;
    function TryGetStrokingAlphaConstant(out Alpha: Single): Boolean;
    function TryGetNonStrokingAlphaConstant(out Alpha: Single): Boolean;
    function GetAlphaSourceFlag: Boolean;
    function GetTextKnockoutFlag: Boolean;
    // BlendMode.getInstance: the name, or the first recognised name of an array. Normal for anything else; Compatible is Normal.
    function GetBlendModeName: string;
    // The /SMask entry as it is (a name or a dictionary); False when missing
    function TryGetSoftMask(out SoftMask: TCosBase): Boolean;
    // /TR and /TR2: nil when missing or an array that does not have four items
    function GetTransfer: TCosBase;
    function GetTransfer2: TCosBase;

    property CosObject: TCosDictionary read FDictionary;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Name,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.Number,
  Pdf4D.Font.Base,
  Pdf4D.Font.Factory;

const
  TransferArrayLength = 4;
  DashPatternLength = 2;
  NoValue = -1;
  BlendModeNames: array[0..16] of string = (TCosNames.Normal, TCosNames.Compatible, TCosNames.Multiply, TCosNames.Screen, TCosNames.Overlay,
                                            TCosNames.Darken, TCosNames.Lighten, TCosNames.ColorDodge, TCosNames.ColorBurn,
                                            TCosNames.HardLight, TCosNames.SoftLight, TCosNames.Difference, TCosNames.Exclusion,
                                            TCosNames.Hue, TCosNames.Saturation, TCosNames.Color, TCosNames.Luminosity);

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


function TPDExtendedGraphicsState.TryGetFloatItem(const Key: string; out Value: Single): Boolean;
begin
  var Item: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(Key, Item) and (Item is TCosNumber));
  if Result then
  begin
    Value := TCosNumber(Item).FloatValue;
  end
  else
  begin
    Value := 0;
  end;
end;

function TPDExtendedGraphicsState.TryGetLineWidth(out Width: Single): Boolean;
begin
  Result := TryGetFloatItem(TCosNames.LW, Width);
end;

function TPDExtendedGraphicsState.GetLineCapStyle: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.LC, NoValue);
end;

function TPDExtendedGraphicsState.GetLineJoinStyle: Integer;
begin
  Result := FDictionary.GetInt(TCosNames.LJ, NoValue);
end;

function TPDExtendedGraphicsState.TryGetMiterLimit(out Limit: Single): Boolean;
begin
  Result := TryGetFloatItem(TCosNames.ML, Limit);
end;

function TPDExtendedGraphicsState.TryGetLineDashPattern(out DashArray: TCosArray; out Phase: Integer): Boolean;
begin
  DashArray := nil;
  Phase := 0;
  var Pattern: TCosArray;
  Result := (FDictionary.TryGetCosArray(TCosNames.D, Pattern) and (Pattern.Count = DashPatternLength));
  if not Result then
  begin
    Exit;
  end;

  const Dashes = Pattern.GetObject(0);
  const PhaseValue = Pattern.GetObject(1);
  Result := ((Dashes is TCosArray) and (PhaseValue is TCosNumber));
  if Result then
  begin
    DashArray := TCosArray(Dashes);
    Phase := TCosNumber(PhaseValue).IntValue;
  end;
end;

function TPDExtendedGraphicsState.TryGetRenderingIntent(out Intent: string): Boolean;
begin
  var Item: TCosBase;
  Result := (FDictionary.TryGetDictionaryObject(TCosNames.RI, Item) and (Item is TCosName));
  if Result then
  begin
    Intent := TCosName(Item).Name;
  end
  else
  begin
    Intent := '';
  end;
end;

function TPDExtendedGraphicsState.TryGetFlatnessTolerance(out Flatness: Single): Boolean;
begin
  Result := TryGetFloatItem(TCosNames.FL, Flatness);
end;

function TPDExtendedGraphicsState.GetAutomaticStrokeAdjustment: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.SA, False);
end;

function TPDExtendedGraphicsState.TryGetStrokingAlphaConstant(out Alpha: Single): Boolean;
begin
  Result := TryGetFloatItem(TCosNames.CA, Alpha);
end;

function TPDExtendedGraphicsState.TryGetNonStrokingAlphaConstant(out Alpha: Single): Boolean;
begin
  Result := TryGetFloatItem(TCosNames.CaNs, Alpha);
end;

function TPDExtendedGraphicsState.GetAlphaSourceFlag: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.AIS, False);
end;

function TPDExtendedGraphicsState.GetTextKnockoutFlag: Boolean;
begin
  Result := FDictionary.GetBoolean(TCosNames.TK, True);
end;

class function TPDExtendedGraphicsState.IsBlendModeName(const Name: string): Boolean;
begin
  Result := False;
  for var Known in BlendModeNames do
  begin
    Result := (Result or (Known = Name));
  end;
end;

function TPDExtendedGraphicsState.GetBlendModeName: string;
begin
  Result := TCosNames.Normal;
  var Item: TCosBase;
  if not FDictionary.TryGetDictionaryObject(TCosNames.BM, Item) then
  begin
    Exit;
  end;

  if Item is TCosName then
  begin
    const Candidate = TCosName(Item).Name;
    if IsBlendModeName(Candidate) then
    begin
      Result := Candidate;
    end;
  end
  else if Item is TCosArray then
  begin
    for var Index := 0 to TCosArray(Item).Count - 1 do
    begin
      const Entry = TCosArray(Item).GetObject(Index);
      if (Entry is TCosName) and IsBlendModeName(TCosName(Entry).Name) then
      begin
        Result := TCosName(Entry).Name;
        Break;
      end;
    end;
  end;

  if Result = TCosNames.Compatible then
  begin
    Result := TCosNames.Normal;
  end;
end;

function TPDExtendedGraphicsState.TryGetSoftMask(out SoftMask: TCosBase): Boolean;
begin
  Result := FDictionary.TryGetDictionaryObject(TCosNames.SMask, SoftMask);
end;

function TPDExtendedGraphicsState.GetTransferItem(const Key: string): TCosBase;
begin
  var Item: TCosBase;
  if not FDictionary.TryGetDictionaryObject(Key, Item) then
  begin
    Exit(nil);
  end;

  const IsWrongArray = ((Item is TCosArray) and (TCosArray(Item).Count <> TransferArrayLength));
  if IsWrongArray then
  begin
    Exit(nil);
  end;

  Result := Item;
end;

function TPDExtendedGraphicsState.GetTransfer: TCosBase;
begin
  Result := GetTransferItem(TCosNames.TR);
end;

function TPDExtendedGraphicsState.GetTransfer2: TCosBase;
begin
  Result := GetTransferItem(TCosNames.TR2);
end;

end.
