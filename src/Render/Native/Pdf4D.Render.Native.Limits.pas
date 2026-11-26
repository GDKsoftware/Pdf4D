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
    // The work that the scan converter may spend on the edges of one path (a unit is about 3 per edge in a row of the walk, a row of an
    // anti-aliased walk being a quarter of a pixel row); an upper bound of it is taken before the walk, and a path over it raises
    // EPdfLimitExceededException before it changes a pixel. A clip path over it raises at the draw that builds the clip.
    MaxEdgeWork: Int64;

    class function Default: TPdfNativeLimits; static;
  end;

implementation

const
  // The peak memory of a draw is about 350 bytes per verb. A 32-bit process has 2 to 4 GB of address space for the whole viewer, so
  // Win32 gets a lower default.
{$IFDEF CPUX86}
  DefaultMaxPathVerbs = 1048576;
{$ELSE}
  DefaultMaxPathVerbs = 4194304;
{$ENDIF}
  DefaultMaxEdgeWork = 800000000;

{ TPdfNativeLimits }

class function TPdfNativeLimits.Default: TPdfNativeLimits;
begin
  Result.MaxPathVerbs := DefaultMaxPathVerbs;
  Result.MaxEdgeWork := DefaultMaxEdgeWork;
end;

end.
