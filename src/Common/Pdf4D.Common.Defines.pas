// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Contains code derived from Apache PDFBox, Copyright The Apache Software Foundation; see the NOTICE file.
unit Pdf4D.Common.Defines;

interface

uses
  System.SysUtils,
  System.Classes;

type
  {$SCOPEDENUMS ON}
  TPdfLogLevel = (Debug, Info, Warning, Error);
  {$SCOPEDENUMS OFF}

  EPdfException = class(Exception);
  EPdfParseException = class(EPdfException);
  EPdfInvalidPasswordException = class(EPdfException);
  EPdfUnsupportedFeatureException = class(EPdfException);
  EPdfLimitExceededException = class(EPdfException);
  // The file cannot be opened (it does not exist, it is locked, or access is denied)
  EPdfFileException = class(EPdfException);

  TPdfLogEvent = reference to procedure(const Level: TPdfLogLevel; const Message: string);

  TPdfFailure = record
    // True for an exception that comes from the data of a file and not from a mistake in the library: the load turns
    // it into an EPdfParseException. PDFBox sees these as an IOException.
    class function IsInputFailure(const Failure: Exception): Boolean; static;
  end;

  TPdfLoadOptions = record
    Password: string;
    MaxDecodedStreamSize: Int64;
    MaxNestingDepth: Integer;
    OnLog: TPdfLogEvent;

    class function Default: TPdfLoadOptions; static;
  end;

const
  DefaultMaxDecodedStreamSize: Int64 = 256 * 1024 * 1024;
  // Same limit as BaseParser.MAX_RECURSION_DEPTH in PDFBox
  DefaultMaxNestingDepth = 500;
  // A caller's MaxNestingDepth is clamped to this: the parser recurses, and deeper nesting could overflow the stack
  MaximumNestingDepth = 2000;

implementation

{ TPdfFailure }

class function TPdfFailure.IsInputFailure(const Failure: Exception): Boolean;
begin
  Result := ((Failure is EOutOfMemory) or (Failure is ERangeError) or (Failure is EIntOverflow) or (Failure is EStreamError));
end;

{ TPdfLoadOptions }

class function TPdfLoadOptions.Default: TPdfLoadOptions;
begin
  Result.Password             := '';
  Result.MaxDecodedStreamSize := DefaultMaxDecodedStreamSize;
  Result.MaxNestingDepth      := DefaultMaxNestingDepth;
  Result.OnLog                := nil;
end;

end.
