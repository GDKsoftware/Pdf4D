// Licensed under the Apache License, Version 2.0; see the LICENSE file.
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
    // it into an EPdfParseException. PDFBox sees these as an IOException. EMathError is the floating point overflow or
    // invalid operation that Java would turn into Infinity or NaN (see TPdfFloatGuard).
    class function IsInputFailure(const Failure: Exception): Boolean; static;
    // True for an exception that no code may swallow: a mistake in the library or the runtime (access violation, stack
    // overflow and other external exceptions, invalid pointer) or an abort
    class function IsFatal(const Failure: Exception): Boolean; static;
  end;

  TPdfLoadOptions = record
    Password: string;
    MaxDecodedStreamSize: Int64;
    MaxNestingDepth: Integer;
    // Nesting of Form XObjects (and Type 3 glyph procedures) while interpreting a content stream
    MaxFormXObjectDepth: Integer;
    // Operators that one page may execute, summed over its content streams and forms
    MaxOperatorsPerPage: Int64;
    // Glyphs that one page may show
    MaxGlyphsPerPage: Integer;
    // Bytes of the data of one inline image (between ID and EI)
    MaxInlineImageSize: Integer;
    // Depth of the q/Q stack
    MaxGraphicsStateDepth: Integer;
    // Mappings (character, CID and CID range entries) that all ToUnicode CMaps of one document may add up to. A CMap
    // that takes the total over the limit is dropped, and so is every ToUnicode CMap that follows.
    MaxToUnicodeMappings: Int64;
    // Decoded bytes of content that one page may run: its content streams and every run of a form XObject, a form that is
    // drawn again counting again
    MaxContentBytesPerPage: Int64;
    OnLog: TPdfLogEvent;

    class function Default: TPdfLoadOptions; static;
  end;

const
  DefaultMaxDecodedStreamSize: Int64 = 256 * 1024 * 1024;
  // Same limit as BaseParser.MAX_RECURSION_DEPTH in PDFBox
  DefaultMaxNestingDepth = 500;
  // A caller's MaxNestingDepth is clamped to this: the parser recurses, and deeper nesting could overflow the stack
  MaximumNestingDepth = 2000;
  // Same limit as PDFStreamEngine.drawObject in PDFBox (level > 50)
  DefaultMaxFormXObjectDepth = 50;
  DefaultMaxOperatorsPerPage: Int64 = 10000000;
  DefaultMaxGlyphsPerPage = 2000000;
  DefaultMaxInlineImageSize = 16 * 1024 * 1024;
  DefaultMaxGraphicsStateDepth = 4096;
  // Four times the limit of one CMap (4194304 mappings): a document of ordinary size is never near it
  DefaultMaxToUnicodeMappings: Int64 = 16777216;
  DefaultMaxContentBytesPerPage: Int64 = 256 * 1024 * 1024;
  // Operands before one operator, and items of one array in a content stream; what comes after is dropped
  MaxContentOperands = 65536;

implementation

{ TPdfFailure }

class function TPdfFailure.IsInputFailure(const Failure: Exception): Boolean;
begin
  Result := ((Failure is EOutOfMemory) or (Failure is ERangeError) or (Failure is EIntOverflow) or (Failure is EStreamError) or (Failure is EMathError));
end;

class function TPdfFailure.IsFatal(const Failure: Exception): Boolean;
begin
  Result := (((Failure is EExternal) and (not IsInputFailure(Failure))) or (Failure is EInvalidPointer) or (Failure is EAbort));
end;

{ TPdfLoadOptions }

class function TPdfLoadOptions.Default: TPdfLoadOptions;
begin
  Result.Password             := '';
  Result.MaxDecodedStreamSize := DefaultMaxDecodedStreamSize;
  Result.MaxNestingDepth      := DefaultMaxNestingDepth;
  Result.MaxFormXObjectDepth  := DefaultMaxFormXObjectDepth;
  Result.MaxOperatorsPerPage  := DefaultMaxOperatorsPerPage;
  Result.MaxGlyphsPerPage     := DefaultMaxGlyphsPerPage;
  Result.MaxInlineImageSize   := DefaultMaxInlineImageSize;
  Result.MaxGraphicsStateDepth := DefaultMaxGraphicsStateDepth;
  Result.MaxToUnicodeMappings := DefaultMaxToUnicodeMappings;
  Result.MaxContentBytesPerPage := DefaultMaxContentBytesPerPage;
  Result.OnLog                := nil;
end;

end.
