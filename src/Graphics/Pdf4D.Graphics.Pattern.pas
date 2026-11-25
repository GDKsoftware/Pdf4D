// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/pattern/PDTilingPattern.java and PDAbstractPattern.java (3.0.8), the read
// side
unit Pdf4D.Graphics.Pattern;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Matrix,
  Pdf4D.Cos.Base,
  Pdf4D.Cos.Dictionary,
  Pdf4D.Model.Rectangle;

const
  TilingPatternType = 1;
  PaintTypeColored = 1;
  PaintTypeUncolored = 2;

type
  // A view on the stream of a tiling pattern (PatternType 1). It owns nothing; the stream belongs to the document.
  TPDTilingPattern = class
  private
    FStream: TCosStream;

  public
    // Value is the pattern as the resources give it. Raises EPdfParseException for a value that is no stream of PatternType 1.
    constructor Create(const Value: TCosBase);

    // 0 when /PaintType is missing, as in PDFBox; anything but 1 is an uncoloured pattern
    function PaintType: Integer;
    function TilingType: Integer;
    function XStep: Single;
    function YStep: Single;
    // The identity without /Matrix
    function Matrix: TPdfMatrix;
    // False without /BBox
    function TryGetBBox(out BBox: TPdfRectangle): Boolean;
    // False without /Resources: the stream then uses the resources of the stream it is painted in
    function TryGetResources(out Resources: TCosDictionary): Boolean;

    property Stream: TCosStream read FStream;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.Cos.Names,
  Pdf4D.Cos.PdfArray;

resourcestring
  PatternIsNoStream = 'A tiling pattern is a stream, not %s';
  PatternIsNoTilingPattern = 'The pattern is of type %d, not a tiling pattern';

{ TPDTilingPattern }

constructor TPDTilingPattern.Create(const Value: TCosBase);
begin
  if not (Value is TCosStream) then
  begin
    var Description := 'nothing';
    if Assigned(Value) then
    begin
      Description := Value.ClassName;
    end;
    raise EPdfParseException.CreateFmt(PatternIsNoStream, [Description]);
  end;

  inherited Create;
  FStream := TCosStream(Value);

  const PatternType = FStream.GetInt(TCosNames.PatternType, 0);
  if PatternType <> TilingPatternType then
  begin
    raise EPdfParseException.CreateFmt(PatternIsNoTilingPattern, [PatternType]);
  end;
end;

function TPDTilingPattern.PaintType: Integer;
begin
  Result := FStream.GetInt(TCosNames.PaintType, 0);
end;

function TPDTilingPattern.TilingType: Integer;
begin
  Result := FStream.GetInt(TCosNames.TilingType, 0);
end;

function TPDTilingPattern.XStep: Single;
begin
  Result := FStream.GetFloat(TCosNames.XStep, 0);
end;

function TPDTilingPattern.YStep: Single;
begin
  Result := FStream.GetFloat(TCosNames.YStep, 0);
end;

function TPDTilingPattern.Matrix: TPdfMatrix;
begin
  var Value: TCosBase;
  if FStream.TryGetDictionaryObject(TCosNames.Matrix, Value) and (Value is TCosArray) then
  begin
    Result := TPdfMatrix.FromCosArray(TCosArray(Value));
  end
  else
  begin
    Result := TPdfMatrix.Identity;
  end;
end;

function TPDTilingPattern.TryGetBBox(out BBox: TPdfRectangle): Boolean;
begin
  var Values: TCosArray;
  Result := FStream.TryGetCosArray(TCosNames.BBox, Values);
  if Result then
  begin
    BBox := TPdfRectangle.FromCosArray(Values);
  end
  else
  begin
    BBox := Default(TPdfRectangle);
  end;
end;

function TPDTilingPattern.TryGetResources(out Resources: TCosDictionary): Boolean;
begin
  Result := FStream.TryGetCosDictionary(TCosNames.Resources, Resources);
  if not Result then
  begin
    Resources := nil;
  end;
end;

end.
