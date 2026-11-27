// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
// Port of: tiny-skia v0.12.0 src/blitter.rs
// Copyright (c) 2006 The Android Open Source Project, (c) 2020 Yevhenii Reizner. BSD-3-Clause, see licenses/tiny-skia-BSD-3-Clause.txt.
unit Pdf4D.Render.Native.Blitter;

{$EXCESSPRECISION OFF}

interface

uses
  System.SysUtils,
  Pdf4D.Render.Native.Geometry,
  Pdf4D.Render.Native.AlphaRuns;

type
  // The `Mask` of blitter.rs, which describes an alpha bitmap of at most two pixels (the `Mask` of mask.rs is TTsMask in
  // Pdf4D.Render.Native.Mask). The two bytes are the alphas of a run, or of the two pixels of BlitAntiH2 and BlitAntiV2; a RowBytes of
  // zero reuses the one row for all of the height.
  TTsBlitterMask = record
    Image: array[0..1] of Byte;
    Bounds: TTsScreenIntRect;
    RowBytes: Cardinal;
  end;

  // Blitter is responsible for actually writing pixels into memory. Besides efficiency, they handle clipping and antialiasing. An object
  // that implements Blitter contains all the context needed to generate pixels for the destination and how src/generated pixels map to the
  // destination. The coordinates passed to the `blit_*` calls are in destination pixel space.
  //
  // The default of every method is `unreachable!()` in Rust and raises EInvalidOpException here: a blitter overrides what its caller uses.
  TTsBlitter = class abstract
  private
    class procedure RaiseNotImplemented(const MethodName: string); static;

  public
    // Blits a horizontal run of one or more pixels
    procedure BlitH(const X, Y, Width: Cardinal); virtual;

    // Blits a horizontal run of antialiased pixels.
    //
    // Runs is a *sparse* zero-terminated run-length encoding of spans of constant alpha values. The runs and the antialias values work
    // together to represent long runs of pixels with the same alphas. An entry in the runs array contains the number of pixels (np) that
    // have the same alpha value; the next np value is found np entries away. For example, if runs[0] = 7, then the next valid entry will
    // be at runs[7]. The two arrays are coupled by index: if the np entry is at runs[45] = 12 then the alpha value can be found at
    // antialias[45] = $88, which means an alpha of $88 for the next 12 pixels starting at pixel 45.
    //
    // Offset is the index where the slice of the Rust signature starts in both arrays.
    procedure BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Offset: Integer); virtual;

    // Blits a vertical run of pixels with a constant alpha value
    procedure BlitV(const X, Y, Height: Cardinal; const Alpha: Byte); virtual;

    procedure BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); virtual;
    procedure BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte); virtual;

    // Blits a solid rectangle one or more pixels wide
    procedure BlitRect(const Rect: TTsScreenIntRect); virtual;

    // Blits a pattern of pixels defined by a rectangle-clipped mask
    procedure BlitMask(const Mask: TTsBlitterMask; const Clip: TTsScreenIntRect); virtual;
  end;

implementation

{ TTsBlitter }

class procedure TTsBlitter.RaiseNotImplemented(const MethodName: string);
begin
  raise EInvalidOpException.CreateFmt('Blitter.%s is not implemented by this blitter', [MethodName]);
end;

procedure TTsBlitter.BlitH(const X, Y, Width: Cardinal);
begin
  RaiseNotImplemented('BlitH');
end;

procedure TTsBlitter.BlitAntiH(const X, Y: Cardinal; const Antialias: TArray<Byte>; const Runs: TArray<TTsAlphaRun>; const Offset: Integer);
begin
  RaiseNotImplemented('BlitAntiH');
end;

procedure TTsBlitter.BlitV(const X, Y, Height: Cardinal; const Alpha: Byte);
begin
  RaiseNotImplemented('BlitV');
end;

procedure TTsBlitter.BlitAntiH2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  RaiseNotImplemented('BlitAntiH2');
end;

procedure TTsBlitter.BlitAntiV2(const X, Y: Cardinal; const Alpha0, Alpha1: Byte);
begin
  RaiseNotImplemented('BlitAntiV2');
end;

procedure TTsBlitter.BlitRect(const Rect: TTsScreenIntRect);
begin
  RaiseNotImplemented('BlitRect');
end;

procedure TTsBlitter.BlitMask(const Mask: TTsBlitterMask; const Clip: TTsScreenIntRect);
begin
  RaiseNotImplemented('BlitMask');
end;

end.
