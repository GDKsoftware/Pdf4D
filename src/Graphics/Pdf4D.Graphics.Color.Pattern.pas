// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: pdfbox/src/main/java/org/apache/pdfbox/pdmodel/graphics/color/PDPattern.java (3.0.8), the name /Pattern without an underlying
// colour space (a coloured pattern); the colour of such a pattern is the name of a pattern of the resources
unit Pdf4D.Graphics.Color.Pattern;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.SharedInstance,
  Pdf4D.Graphics.Color;

type
  // Shared by all documents and threads: the space holds no state
  TPDPattern = class(TPDColorSpace)
  private
    class var FInstance: TPdfSharedInstance<TPDPattern>;

    class destructor Destroy;

  public
    class function Instance: TPDPattern; static;
    // A pattern colour: the name of a pattern of /Pattern in the resources
    class function ColorOf(const PatternName: string): TPDColor; static;

    function Name: string; override;
    // A pattern colour has no components of its own
    function NumberOfComponents: Integer; override;
    function InitialColor: TPDColor; override;
    // Raises EInvalidOpException: the colour comes from the pattern, not from components
    function ToRgb(const Components: TArray<Single>): TPdfRgb; override;
  end;

implementation

uses
  Pdf4D.Cos.Names;

resourcestring
  PatternHasNoRgb = 'A pattern colour has no RGB value of its own';

{ TPDPattern }

class destructor TPDPattern.Destroy;
begin
  FInstance.Release;
end;

class function TPDPattern.Instance: TPDPattern;
begin
  Result := FInstance.Get(
    function: TPDPattern
    begin
      Result := TPDPattern.Create;
    end);
end;

class function TPDPattern.ColorOf(const PatternName: string): TPDColor;
begin
  Result := TPDColor.Create(Instance, nil);
  Result.PatternName := PatternName;
end;

function TPDPattern.Name: string;
begin
  Result := TCosNames.Pattern;
end;

function TPDPattern.NumberOfComponents: Integer;
begin
  Result := 0;
end;

function TPDPattern.InitialColor: TPDColor;
begin
  Result := TPDColor.Create(Self, nil);
end;

function TPDPattern.ToRgb(const Components: TArray<Single>): TPdfRgb;
begin
  raise EInvalidOpException.Create(PatternHasNoRgb);
end;

end.
