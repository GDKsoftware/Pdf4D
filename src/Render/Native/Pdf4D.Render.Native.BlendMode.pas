// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/blend_mode.rs
// Copyright (c) 2011 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.BlendMode;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Stage;

type
  // A blending mode, with the values of tiny-skia in the same order. The default of tiny-skia is SourceOver.
  TTsBlendMode = (
    // Replaces destination with zero: fully transparent
    Clear,
    // Replaces destination
    Source,
    // Preserves destination
    Destination,
    // Source over destination
    SourceOver,
    // Destination over source
    DestinationOver,
    // Source trimmed inside destination
    SourceIn,
    // Destination trimmed by source
    DestinationIn,
    // Source trimmed outside destination
    SourceOut,
    // Destination trimmed outside source
    DestinationOut,
    // Source inside destination blended with destination
    SourceAtop,
    // Destination inside source blended with source
    DestinationAtop,
    // Each of source and destination trimmed outside the other
    &Xor,
    // Sum of colors
    Plus,
    // Product of premultiplied colors; darkens destination
    Modulate,
    // Multiply inverse of pixels, inverting result; brightens destination
    Screen,
    // Multiply or screen, depending on destination
    Overlay,
    // Darker of source and destination
    Darken,
    // Lighter of source and destination
    Lighten,
    // Brighten destination to reflect source
    ColorDodge,
    // Darken destination to reflect source
    ColorBurn,
    // Multiply or screen, depending on source
    HardLight,
    // Lighten or darken, depending on source
    SoftLight,
    // Subtract darker from lighter with higher contrast
    Difference,
    // Subtract darker from lighter with lower contrast
    Exclusion,
    // Multiply source with destination, darkening image
    Multiply,
    // Hue of source with saturation and luminosity of destination
    Hue,
    // Saturation of source with hue and luminosity of destination
    Saturation,
    // Hue and saturation of source with luminosity of destination
    Color,
    // Luminosity of source with hue and saturation of destination
    Luminosity
  );

  TTsBlendModeHelper = record helper for TTsBlendMode
    // Never pre-scale with rgb coverage if the blend mode involves a source-alpha term; always pre-scale Plus. This is a finer-grained
    // breakdown of SkBlendMode_SupportsCoverageAsAlpha().
    function ShouldPreScaleCoverage: Boolean;

    // `to_stage`: False for Source, whose stage is a no-op
    function TryToStage(out Stage: TTsStage): Boolean;
  end;

implementation

{ TTsBlendModeHelper }

function TTsBlendModeHelper.ShouldPreScaleCoverage: Boolean;
begin
  Result := (Self in [TTsBlendMode.Destination,      // d              --> no sa term, ok!
                      TTsBlendMode.DestinationOver,  // d + s*inv(da)  --> no sa term, ok!
                      TTsBlendMode.Plus,             // clamp(s+d)     --> no sa term, ok!
                      TTsBlendMode.DestinationOut,   // d * inv(sa)
                      TTsBlendMode.SourceAtop,       // s*da + d*inv(sa)
                      TTsBlendMode.SourceOver,       // s + d*inv(sa)
                      TTsBlendMode.&Xor]);           // s*inv(da) + d*inv(sa)
end;

function TTsBlendModeHelper.TryToStage(out Stage: TTsStage): Boolean;
begin
  Stage := TTsStage.MoveSourceToDestination;

  case Self of
    TTsBlendMode.Clear           : Stage := TTsStage.Clear;
    TTsBlendMode.Source          : Exit(False);
    TTsBlendMode.Destination     : Stage := TTsStage.MoveDestinationToSource;
    TTsBlendMode.SourceOver      : Stage := TTsStage.SourceOver;
    TTsBlendMode.DestinationOver : Stage := TTsStage.DestinationOver;
    TTsBlendMode.SourceIn        : Stage := TTsStage.SourceIn;
    TTsBlendMode.DestinationIn   : Stage := TTsStage.DestinationIn;
    TTsBlendMode.SourceOut       : Stage := TTsStage.SourceOut;
    TTsBlendMode.DestinationOut  : Stage := TTsStage.DestinationOut;
    TTsBlendMode.SourceAtop      : Stage := TTsStage.SourceAtop;
    TTsBlendMode.DestinationAtop : Stage := TTsStage.DestinationAtop;
    TTsBlendMode.&Xor            : Stage := TTsStage.&Xor;
    TTsBlendMode.Plus            : Stage := TTsStage.Plus;
    TTsBlendMode.Modulate        : Stage := TTsStage.Modulate;
    TTsBlendMode.Screen          : Stage := TTsStage.Screen;
    TTsBlendMode.Overlay         : Stage := TTsStage.Overlay;
    TTsBlendMode.Darken          : Stage := TTsStage.Darken;
    TTsBlendMode.Lighten         : Stage := TTsStage.Lighten;
    TTsBlendMode.ColorDodge      : Stage := TTsStage.ColorDodge;
    TTsBlendMode.ColorBurn       : Stage := TTsStage.ColorBurn;
    TTsBlendMode.HardLight       : Stage := TTsStage.HardLight;
    TTsBlendMode.SoftLight       : Stage := TTsStage.SoftLight;
    TTsBlendMode.Difference      : Stage := TTsStage.Difference;
    TTsBlendMode.Exclusion       : Stage := TTsStage.Exclusion;
    TTsBlendMode.Multiply        : Stage := TTsStage.Multiply;
    TTsBlendMode.Hue             : Stage := TTsStage.Hue;
    TTsBlendMode.Saturation      : Stage := TTsStage.Saturation;
    TTsBlendMode.Color           : Stage := TTsStage.Color;
    TTsBlendMode.Luminosity      : Stage := TTsStage.Luminosity;
  else
    raise ENotSupportedException.CreateFmt('Unsupported blend mode: %d', [Ord(Self)]);
  end;

  Result := True;
end;

end.
