unit Pdf4D.Common.Defines;

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TPdfLogLevel = (Debug, Info, Warning, Error);
  {$SCOPEDENUMS OFF}

  EPdfException = class(Exception);
  EPdfParseException = class(EPdfException);
  EPdfInvalidPasswordException = class(EPdfException);
  EPdfUnsupportedFeatureException = class(EPdfException);
  EPdfLimitExceededException = class(EPdfException);

  TPdfLogEvent = reference to procedure(const Level: TPdfLogLevel; const Message: string);

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

{ TPdfLoadOptions }

class function TPdfLoadOptions.Default: TPdfLoadOptions;
begin
  Result.Password             := '';
  Result.MaxDecodedStreamSize := DefaultMaxDecodedStreamSize;
  Result.MaxNestingDepth      := DefaultMaxNestingDepth;
  Result.OnLog                := nil;
end;

end.
