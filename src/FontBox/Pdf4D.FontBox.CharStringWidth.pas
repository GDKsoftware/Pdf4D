// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
// Port of: fontbox/src/main/java/org/apache/fontbox/cff/Type1CharStringParser.java, Type2CharStringParser.java,
// Type2CharString.java and the width handling of Type1CharString.java (3.0.8)
unit Pdf4D.FontBox.CharStringWidth;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Common.Log;

const
  // The deepest nesting of callsubr and callgsubr; a deeper call stops the interpretation
  MaxSubrDepth = 10;
  // The most tokens (numbers and operators, subroutines included) that one charstring may take
  MaxOperations = 65536;
  // The most operands that may wait for an operator
  MaxOperands = 513;

type
  // Reads the advance width from a charstring. Nothing is drawn: the interpretation ends at the operator that gives the width.
  TCharStringWidth = class
  public
    // The width of a Type 1 charstring: the width operand of the first hsbw or sbw. False when the charstring has none, or
    // when it is damaged before it; the problem goes to the log.
    class function Type1Width(const CharString: TBytes; const Subrs: TArray<TBytes>; out Width: Integer;
                              const Log: TPdfLog = nil): Boolean; static;
    // The width of a Type 2 charstring. A charstring that is damaged before the width is known gets DefaultWidthX.
    class function Type2Width(const CharString: TBytes; const GlobalSubrs, LocalSubrs: TArray<TBytes>;
                              const DefaultWidthX, NominalWidthX: Integer; const Log: TPdfLog = nil): Integer; static;
  end;

implementation

uses
  Pdf4D.Common.Defines,
  Pdf4D.FontBox.Cff.Font,
  Pdf4D.FontBox.CharStringReaders;

{ TCharStringWidth }

class function TCharStringWidth.Type1Width(const CharString: TBytes; const Subrs: TArray<TBytes>; out Width: Integer;
                                           const Log: TPdfLog): Boolean;
begin
  Width := 0;
  const Reader = TType1Reader.Create(Subrs, Log);
  try
    try
      Result := Reader.TryReadWidth(CharString, Width);
    except
      on Failure: EPdfParseException do
      begin
        Width := 0;
        Result := False;
        if Assigned(Log) then
        begin
          Log.Warning('Type 1 charstring ignored: %s', [Failure.Message]);
        end;
      end;
    end;
  finally
    Reader.Free;
  end;
end;

class function TCharStringWidth.Type2Width(const CharString: TBytes; const GlobalSubrs, LocalSubrs: TArray<TBytes>;
                                           const DefaultWidthX, NominalWidthX: Integer; const Log: TPdfLog): Integer;
begin
  const Reader = TType2Reader.Create(GlobalSubrs, LocalSubrs, DefaultWidthX, NominalWidthX, Log);
  try
    try
      Result := Reader.ReadWidth(CharString);
    except
      on Failure: EPdfParseException do
      begin
        const Default = Single(DefaultWidthX);
        Result := TCFFNumber.ToInt(Default);
        if Assigned(Log) then
        begin
          Log.Warning('Type 2 charstring ignored, the default width is used: %s', [Failure.Message]);
        end;
      end;
    end;
  finally
    Reader.Free;
  end;
end;

end.
