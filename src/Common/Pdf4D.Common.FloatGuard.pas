// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Common.FloatGuard;

interface

uses
  System.SysUtils,
  System.Math;

type
  // Java float arithmetic never raises: an overflow gives Infinity and an invalid operation gives NaN. Delphi on Win32
  // and Win64 raises EMathError for the same operations, and the exception mask is per thread. This guard masks all
  // floating point exceptions for a stretch of code and restores the previous mask afterwards, so the code behaves as
  // PDFBox does.
  //
  // The content stream engine and the public text API wrap their work with it. Code that is not wrapped must expect
  // EMathError, which TPdfFailure.IsInputFailure treats as an input failure.
  TPdfFloatGuard = record
    // Runs Work with every floating point exception masked and restores the previous mask, also when Work raises
    class procedure Run(const Work: TProc); static;
    // Begin/End pair for code that cannot be wrapped in a callback; hand the result of Enter to Leave
    class function Enter: TArithmeticExceptionMask; static;
    class procedure Leave(const Previous: TArithmeticExceptionMask); static;
  end;

implementation

const
  AllExceptions: TArithmeticExceptionMask = [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision];

{ TPdfFloatGuard }

class procedure TPdfFloatGuard.Run(const Work: TProc);
begin
  const Previous = Enter;
  try
    Work();
  finally
    Leave(Previous);
  end;
end;

class function TPdfFloatGuard.Enter: TArithmeticExceptionMask;
begin
  Result := SetExceptionMask(AllExceptions);
end;

class procedure TPdfFloatGuard.Leave(const Previous: TArithmeticExceptionMask);
begin
  SetExceptionMask(Previous);
end;

end.
