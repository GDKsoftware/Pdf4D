// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Render.Native.Limits;

{$EXCESSPRECISION OFF}

interface

type
  // The limits of the native backend. They are declared here so that the device can use them; Pdf4D.Render.Native.Backend gives the same
  // type its public name.
  TPdfNativeLimits = record
    // Verbs per FillPath, StrokePath and clip path; above that the draw raises EPdfLimitExceededException before it changes a pixel
    MaxPathVerbs: Integer;

    class function Default: TPdfNativeLimits; static;
  end;

implementation

const
  DefaultMaxPathVerbs = 4194304;

{ TPdfNativeLimits }

class function TPdfNativeLimits.Default: TPdfNativeLimits;
begin
  Result.MaxPathVerbs := DefaultMaxPathVerbs;
end;

end.
