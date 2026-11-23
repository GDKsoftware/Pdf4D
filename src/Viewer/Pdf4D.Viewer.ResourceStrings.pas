// Copyright 2026 GDK Software
// Licensed under the Apache License, Version 2.0; see the LICENSE file.
unit Pdf4D.Viewer.ResourceStrings;

interface

resourcestring
  SNoRenderBackend = 'No render backend. Put a TPdf4DSkiaBackend on the form and link it to the document, or set RenderBackend.';
  SOverlayWhileNotOpen = 'An overlay can be added only while the document is open.';
  SOverlayPageOutside = 'Page %d is outside the document.';
  SOverlayNoQuads = 'An overlay needs at least one quad.';
  SOverlayQuadNotFinite = 'The quads of an overlay must have finite coordinates.';
  SDocumentNotOpen = 'The document is not open.';
  SNoStream = 'Open needs a stream.';
implementation

end.
