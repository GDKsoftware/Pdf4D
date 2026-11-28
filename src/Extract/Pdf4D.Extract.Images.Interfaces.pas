// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Extract.Images.Interfaces;

interface

uses
  System.Types,
  System.SysUtils,
  Pdf4D.Common.Matrix;

type
  // One placement of an image on a page. The same XObject drawn twice gives two records with the same ObjectNumber and Generation.
  TPdfImageInfo = record
    PageIndex: Integer;
    // The order of drawing on the page, 0-based
    Index: Integer;
    // Axis aligned, in page coordinates (points, origin at the upper left of the CropBox, /Rotate applied)
    Box: TRectF;
    // The CTM of the unit square in PDF user space
    Matrix: TPdfMatrix;
    PixelWidth: Integer;
    PixelHeight: Integer;
    BitsPerComponent: Integer;
    // 0 when the colour space cannot be made (an image without /ColorSpace, JPX and JBIG2 that carry it in the stream)
    ComponentCount: Integer;
    // The name of the colour space family, for example DeviceRGB, ICCBased or Indexed; empty for a stencil and when it cannot be made
    ColorSpace: string;
    // The names of /Filter in full (an abbreviation of an inline image is spelled out)
    Filters: TArray<string>;
    IsStencil: Boolean;
    // /Mask or /SMask
    HasMask: Boolean;
    IsInline: Boolean;
    // 0, 0 for an inline image, and for an XObject that is a direct object
    ObjectNumber: Integer;
    Generation: Integer;
  end;

  TPdfImageDataFormat = (Jpeg, Png, Raw, None);

  TPdfImageData = record
    Format: TPdfImageDataFormat;
    // image/jpeg, image/png or application/octet-stream
    MimeType: string;
    Bytes: TBytes;
    // Raw only: JPXDecode or JBIG2Decode
    RawFilter: string;
    // Of the encoded image
    Width: Integer;
    Height: Integer;
    Downscaled: Boolean;
    // Format = None: why there is no data
    Error: string;
  end;

  IPdfPageImages = interface
    ['{3E7D1F92-5A48-4C60-B2D9-8F14C6A0E357}']
    // The placements in the order of drawing. Nothing is decoded to find them.
    function Images: TArray<TPdfImageInfo>;
    // The data of one placement; EArgumentOutOfRangeException for an index outside the placements
    function GetData(const Index: Integer): TPdfImageData;
    // The data of all placements in one walk of the page, in the order of Images
    function GetAllData: TArray<TPdfImageData>;
  end;

implementation

end.
