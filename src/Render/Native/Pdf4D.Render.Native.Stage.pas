// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/pipeline/mod.rs (Stage)
// Copyright (c) 2016 Google Inc., (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Stage;

{$EXCESSPRECISION OFF}
{$SCOPEDENUMS ON}

interface

// The enumeration of the pipeline stages, with the names and the order of `Stage` in pipeline/mod.rs. It lives here, and not in the
// pipeline unit, so that the blend modes can name their stage without depending on the pipeline. The stages of the gradients, the conical
// gradients and the gamma functions are not ported but keep their place, so that the order stays the one of tiny-skia.
type
  TTsStage = (
    MoveSourceToDestination,
    MoveDestinationToSource,
    Clamp0,
    ClampA,
    Premultiply,
    UniformColor,
    SeedShader,
    LoadDestination,
    Store,
    LoadDestinationU8,
    StoreU8,
    Gather,
    LoadMaskU8,
    MaskU8,
    ScaleU8,
    LerpU8,
    Scale1Float,
    Lerp1Float,
    DestinationAtop,
    DestinationIn,
    DestinationOut,
    DestinationOver,
    SourceAtop,
    SourceIn,
    SourceOut,
    SourceOver,
    Clear,
    Modulate,
    Multiply,
    Plus,
    Screen,
    &Xor,
    ColorBurn,
    ColorDodge,
    Darken,
    Difference,
    Exclusion,
    HardLight,
    Lighten,
    Overlay,
    SoftLight,
    Hue,
    Saturation,
    Color,
    Luminosity,
    SourceOverRgba,
    Transform,
    Reflect,
    &Repeat,
    Bilinear,
    Bicubic,
    PadX1,
    ReflectX1,
    RepeatX1,
    Gradient,
    EvenlySpaced2StopGradient,
    XYToUnitAngle,
    XYToRadius,
    XYTo2PtConicalFocalOnCircle,
    XYTo2PtConicalWellBehaved,
    XYTo2PtConicalSmaller,
    XYTo2PtConicalGreater,
    XYTo2PtConicalStrip,
    Mask2PtConicalNan,
    Mask2PtConicalDegenerates,
    ApplyVectorMask,
    Alter2PtConicalCompensateFocal,
    Alter2PtConicalUnswap,
    NegateX,
    ApplyConcentricScaleBias,
    GammaExpand2,
    GammaExpandDestination2,
    GammaCompress2,
    GammaExpand22,
    GammaExpandDestination22,
    GammaCompress22,
    GammaExpandSrgb,
    GammaExpandDestinationSrgb,
    GammaCompressSrgb,
    // Pdf4D additions, after the example of decal_x_and_y and check_decal_mask of Skia: see Pdf4D.Render.Native.Pipeline.Highp
    DecalXY,
    CheckDecalMask
  );

implementation

end.
